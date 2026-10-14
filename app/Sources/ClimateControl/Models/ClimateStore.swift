import Foundation
import Observation

/// Single source of truth for the UI: polls the bridge and sends debounced, optimistic updates.
@MainActor
@Observable
final class ClimateStore {
    private(set) var device: ACDevice?
    private(set) var errorMessage: String?
    private(set) var isSending = false
    private(set) var devices: [BridgeClient.DeviceSummary] = []

    /// Explicit choice from the popover's device menu; survives restarts.
    private var selectedDeviceID: Int? {
        get { UserDefaults.standard.object(forKey: "selectedDeviceID") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "selectedDeviceID") }
    }

    private let client: BridgeClient
    private let pollInterval: Duration
    private let debounce: Duration
    private var pollTask: Task<Void, Never>?
    /// Waits out the debounce before flushing. Never cancels a request already on the wire.
    private var debounceTask: Task<Void, Never>?
    private var pendingPatch = StatePatch()
    private var isInteracting = false
    private let isDemo: Bool

    init(client: BridgeClient, pollInterval: Duration = .seconds(60), debounce: Duration = .milliseconds(600)) {
        self.client = client
        self.pollInterval = pollInterval
        self.debounce = debounce
        self.isDemo = false
    }

    /// Offline mode for design work: `CLIMATE_DEMO=1 swift run`.
    init(demo device: ACDevice) {
        self.client = BridgeClient()
        self.pollInterval = .seconds(60)
        self.debounce = .zero
        self.isDemo = true
        self.device = device
        self.devices = [.init(id: device.id, name: device.name, isDefault: true), .init(id: 1, name: "Wohnzimmer")]
    }

    func start() {
        guard pollTask == nil, !isDemo else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(60))
            }
        }
    }

    func refresh(force: Bool = false) async {
        do {
            if devices.isEmpty { devices = try await client.devices() }
            guard let id = activeDeviceID else {
                errorMessage = "Kein Gerät in MELCloud gefunden."
                return
            }
            let fresh = try await client.state(deviceID: id, force: force)
            // Don't overwrite optimistic UI while the user drags or a write is queued/in flight.
            if !hasPendingWork, fresh.id == activeDeviceID { device = fresh }
            errorMessage = nil
        } catch {
            errorMessage = "Bridge nicht erreichbar"
        }
    }

    /// Menu choice > MELCLOUD_DEVICE from bridge/.env > first unit.
    private var activeDeviceID: Int? {
        let ids = devices.map(\.id)
        if let chosen = selectedDeviceID, ids.contains(chosen) { return chosen }
        return devices.first(where: \.isDefault)?.id ?? ids.first
    }

    func selectDevice(_ id: Int) {
        guard id != device?.id else { return }
        selectedDeviceID = id
        if isDemo {
            device?.name = devices.first { $0.id == id }?.name ?? ""
            return
        }
        debounceTask?.cancel()
        debounceTask = nil
        pendingPatch = StatePatch()
        device = nil
        Task { await refresh(force: true) }
    }

    // MARK: Writing

    func update(_ patch: StatePatch) {
        guard var current = device else { return }
        current.apply(patch)
        device = current
        guard !isDemo else { return }
        pendingPatch = pendingPatch.merged(with: patch)
        scheduleFlush()
    }

    /// While the slider is held, values only change locally; one request goes out on release.
    func setInteracting(_ active: Bool) {
        isInteracting = active
        if active {
            debounceTask?.cancel()
            debounceTask = nil
        } else {
            scheduleFlush()
        }
    }

    private var hasPendingWork: Bool {
        isInteracting || isSending || debounceTask != nil || !pendingPatch.isEmpty
    }

    private func scheduleFlush() {
        debounceTask?.cancel()
        guard !isInteracting, !pendingPatch.isEmpty else {
            debounceTask = nil
            return
        }
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.debounceTask = nil
            await self.flush()
        }
    }

    /// Sends the accumulated patch. Strictly one request at a time; changes made meanwhile follow afterwards.
    private func flush() async {
        guard !isSending, !pendingPatch.isEmpty, let deviceID = device?.id else { return }
        let patch = pendingPatch
        pendingPatch = StatePatch()
        isSending = true
        var failed = false
        do {
            let fresh = try await client.patch(deviceID: deviceID, patch)
            // Only adopt the server's view if nothing newer happened locally in the meantime.
            if pendingPatch.isEmpty, !isInteracting, debounceTask == nil, fresh.id == device?.id { device = fresh }
            errorMessage = nil
        } catch {
            errorMessage = "Änderung fehlgeschlagen"
            failed = true
        }
        isSending = false
        if !pendingPatch.isEmpty {
            scheduleFlush()
        } else if failed {
            await refresh(force: true)
        }
    }

    // MARK: Convenience intents for the views

    func togglePower() { update(StatePatch(power: !(device?.power ?? false))) }
    func setTemperature(_ value: Double) { update(StatePatch(targetTemperature: value)) }
    func setMode(_ mode: OperationMode) { update(StatePatch(operationMode: mode)) }
    func setFanSpeed(_ speed: String) { update(StatePatch(fanSpeed: speed)) }
    func setVaneVertical(_ position: String) { update(StatePatch(vaneVertical: position)) }
}
