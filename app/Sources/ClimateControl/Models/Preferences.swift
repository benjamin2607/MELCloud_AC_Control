import Foundation
import Observation
import ServiceManagement

/// User preferences stored in UserDefaults (nothing secret lives here).
@MainActor
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    /// Modes the user chose to hide from the mode picker (e.g. no cooling in winter).
    var hiddenModes: Set<OperationMode> {
        didSet { defaults.set(hiddenModes.map(\.rawValue).sorted(), forKey: "hiddenModes") }
    }

    /// Explicit device choice from the popover menu or Settings; survives restarts.
    var selectedDeviceID: Int? {
        didSet { defaults.set(selectedDeviceID, forKey: "selectedDeviceID") }
    }

    private(set) var launchAtLogin: Bool = false
    private(set) var launchAtLoginNeedsApproval = false

    init() {
        hiddenModes = Set((defaults.stringArray(forKey: "hiddenModes") ?? []).compactMap(OperationMode.init(rawValue:)))
        selectedDeviceID = defaults.object(forKey: "selectedDeviceID") as? Int
        refreshLoginItemStatus()
    }

    func modes(for device: ACDevice) -> [OperationMode] {
        let visible = device.operationModes.filter { !hiddenModes.contains($0) }
        return visible.isEmpty ? device.operationModes : visible
    }

    // MARK: Launch at login

    /// Login items only work for a real .app bundle (not `swift run`).
    var canManageLoginItem: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard canManageLoginItem else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Status below reflects what actually happened; nothing else to do.
        }
        refreshLoginItemStatus()
    }

    /// First launch of the bundled app: start with the Mac by default (can be turned off in Settings).
    /// Only from an Applications folder, so test runs from build/ don't register a login item for that path.
    func enableLaunchAtLoginOnFirstRun() {
        let isInstalled = Bundle.main.bundlePath.contains("/Applications/")
        guard canManageLoginItem, isInstalled, !defaults.bool(forKey: "didConfigureLoginItem") else { return }
        defaults.set(true, forKey: "didConfigureLoginItem")
        setLaunchAtLogin(true)
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }
}
