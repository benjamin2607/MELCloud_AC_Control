import Foundation
import Observation

/// Single source of truth for the UI: polls MELCloud and sends debounced, optimistic updates.
@MainActor
@Observable
final class ClimateStore {
    private(set) var device: ACDevice?
    private(set) var devices: [DeviceSummary] = []
    private(set) var errorMessage: String?
    private(set) var isSending = false
    private(set) var needsSignIn = false
    private(set) var accountEmail: String?

    let preferences: Preferences
    /// Set by the app shell; opens the Settings window (sign-in lives there).
    var openSettings: () -> Void = {}

    private let service: MELCloudService?
    private let pollInterval: Duration
    private let debounce: Duration
    private var pollTask: Task<Void, Never>?
    /// Waits out the debounce before flushing. Never cancels a request already on the wire.
    private var debounceTask: Task<Void, Never>?
    private var pendingPatch = StatePatch()
    private var isInteracting = false

    init(
        service: MELCloudService,
        preferences: Preferences,
        pollInterval: Duration = .seconds(60),
        debounce: Duration = .milliseconds(600)
    ) {
        self.service = service
        self.preferences = preferences
        self.pollInterval = pollInterval
        self.debounce = debounce
        self.accountEmail = service.accountEmail
        self.needsSignIn = !service.isSignedIn
    }

    /// Offline mode for design work: `CLIMATE_DEMO=1`.
    init(demo device: ACDevice, preferences: Preferences) {
        self.service = nil
        self.preferences = preferences
        self.pollInterval = .seconds(60)
        self.debounce = .zero
        self.device = device
        self.devices = [
            DeviceSummary(id: device.id, buildingID: 0, name: device.name),
            DeviceSummary(id: 1, buildingID: 0, name: "Living room"),
        ]
        self.accountEmail = "demo@example.com"
    }

    var isDemo: Bool { service == nil }

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
        guard let service else { return }
        guard service.isSignedIn else {
            needsSignIn = true
            device = nil
            return
        }
        do {
            if devices.isEmpty || force { devices = try await service.devices() }
            guard let id = activeDeviceID else {
                errorMessage = "No air conditioner found in your MELCloud account."
                return
            }
            let fresh = try await service.device(id: id, force: force)
            // Don't overwrite optimistic UI while the user drags or a write is queued/in flight.
            if !hasPendingWork, fresh.id == activeDeviceID { device = fresh }
            errorMessage = nil
            needsSignIn = false
        } catch {
            handle(error)
        }
    }

    // MARK: Account

    func signIn(email: String, password: String) async throws {
        guard let service else { return }
        try await service.signIn(email: email, password: password)
        accountEmail = email
        needsSignIn = false
        errorMessage = nil
        devices = []
        await refresh(force: true)
    }

    func signOut() async {
        guard let service else { return }
        await service.signOut()
        debounceTask?.cancel()
        debounceTask = nil
        pendingPatch = StatePatch()
        device = nil
        devices = []
        accountEmail = nil
        needsSignIn = true
    }

    // MARK: Devices

    /// Menu/Settings choice > first unit of the account.
    private var activeDeviceID: Int? {
        let ids = devices.map(\.id)
        if let chosen = preferences.selectedDeviceID, ids.contains(chosen) { return chosen }
        return ids.first
    }

    func selectDevice(_ id: Int) {
        guard id != device?.id else { return }
        preferences.selectedDeviceID = id
        if isDemo {
            device?.name = devices.first { $0.id == id }?.name ?? ""
            return
        }
        debounceTask?.cancel()
        debounceTask = nil
        pendingPatch = StatePatch()
        device = nil
        Task { await refresh() }
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
        guard let service, !isSending, !pendingPatch.isEmpty, let deviceID = device?.id else { return }
        let patch = pendingPatch
        pendingPatch = StatePatch()
        isSending = true
        var failed = false
        do {
            let fresh = try await service.apply(patch, to: deviceID)
            // Only adopt the server's view if nothing newer happened locally in the meantime.
            if pendingPatch.isEmpty, !isInteracting, debounceTask == nil, fresh.id == device?.id { device = fresh }
            errorMessage = nil
        } catch {
            handle(error, fallback: "Change could not be sent.")
            failed = true
        }
        isSending = false
        if !pendingPatch.isEmpty {
            scheduleFlush()
        } else if failed, !needsSignIn {
            await refresh(force: true)
        }
    }

    private func handle(_ error: Error, fallback: String? = nil) {
        switch error {
        case MELCloudService.ServiceError.notSignedIn, MELCloudService.ServiceError.sessionExpired:
            needsSignIn = true
            device = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
        case let error as LocalizedError:
            errorMessage = error.errorDescription ?? fallback
        default:
            errorMessage = fallback ?? "Something went wrong."
        }
    }

    // MARK: Convenience intents for the views

    func togglePower() { update(StatePatch(power: !(device?.power ?? false))) }
    func setTemperature(_ value: Double) { update(StatePatch(targetTemperature: value)) }
    func setMode(_ mode: OperationMode) { update(StatePatch(operationMode: mode)) }
    func setFanSpeed(_ speed: String) { update(StatePatch(fanSpeed: speed)) }
    func setVaneVertical(_ position: String) { update(StatePatch(vaneVertical: position)) }
}
