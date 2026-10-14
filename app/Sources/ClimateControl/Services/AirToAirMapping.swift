import Foundation

/// Translates between MELCloud's raw air-to-air (ATA, DeviceType 0) JSON and `ACDevice`.
/// Codes and capability rules mirror python-melcloud's `ata_device.py` (MIT), see NOTICE.
enum AirToAirMapping {
    enum MappingError: Error, Equatable {
        case unsupported(String)
    }

    // EffectiveFlags tell MELCloud which fields of a posted state actually changed.
    private static let flagPower = 0x01
    private static let flagMode = 0x02
    private static let flagTemperature = 0x04
    private static let flagFanSpeed = 0x08
    private static let flagVaneVertical = 0x10

    private static let modeCodes: [Int: OperationMode] = [1: .heat, 2: .dry, 3: .cool, 7: .fanOnly, 8: .heatCool]
    private static let vaneCodes: [Int: String] = [0: "auto", 1: "1_up", 2: "2", 3: "3", 4: "4", 5: "5_down", 7: "swing"]

    static func isAirToAir(_ conf: JSONObject) -> Bool {
        conf["Device"]?.object?["DeviceType"]?.int == 0
    }

    static func summary(_ conf: JSONObject) -> DeviceSummary? {
        guard let id = conf["DeviceID"]?.int, let buildingID = conf["BuildingID"]?.int else { return nil }
        return DeviceSummary(id: id, buildingID: buildingID, name: conf["DeviceName"]?.string ?? "Device \(id)")
    }

    static func device(conf: JSONObject, state: JSONObject) -> ACDevice {
        let caps = conf["Device"]?.object ?? [:]
        let mode = state["OperationMode"]?.int.flatMap { modeCodes[$0] } ?? .undefined
        let (minKey, maxKey) = temperatureKeys(for: mode)
        let hasOutdoor = caps["HasOutdoorTemperature"]?.bool == true && conf["HideOutdoorTemperature"]?.bool != true
        let hasError = state["HasError"]?.bool ?? false

        return ACDevice(
            id: conf["DeviceID"]?.int ?? 0,
            name: conf["DeviceName"]?.string ?? "",
            power: state["Power"]?.bool ?? false,
            roomTemperature: state["RoomTemperature"]?.double,
            outdoorTemperature: hasOutdoor ? caps["OutdoorTemperature"]?.double : nil,
            targetTemperature: state["SetTemperature"]?.double ?? 20,
            targetTemperatureMin: caps[minKey]?.double ?? 10,
            targetTemperatureMax: caps[maxKey]?.double ?? 31,
            targetTemperatureStep: caps["TemperatureIncrement"]?.double ?? 0.5,
            operationMode: mode,
            operationModes: operationModes(caps),
            fanSpeed: state["SetFanSpeed"]?.int.map { $0 == 0 ? "auto" : String($0) },
            fanSpeeds: fanSpeeds(caps: caps, state: state),
            vaneVertical: state["VaneVertical"]?.int.flatMap { vaneCodes[$0] },
            vaneVerticalPositions: vanePositions(conf: conf, caps: caps),
            hasError: hasError,
            // MELCloud reports 8000 ("no error") on healthy units; only surface real errors.
            errorCode: hasError ? state["ErrorCode"]?.int.map(String.init) : nil
        )
    }

    /// Applies a patch to a raw state for posting to Device/SetAta. Validates against the device's capabilities.
    static func apply(_ patch: StatePatch, to state: JSONObject, conf: JSONObject) throws -> JSONObject {
        let current = device(conf: conf, state: state)
        var next = state
        var flags = 0

        if let power = patch.power {
            next["Power"] = .bool(power)
            flags |= flagPower
        }
        if let mode = patch.operationMode {
            guard current.operationModes.contains(mode), let code = modeCodes.first(where: { $0.value == mode })?.key else {
                throw MappingError.unsupported("operation mode \(mode.rawValue)")
            }
            next["OperationMode"] = .number(Double(code))
            flags |= flagMode
        }
        if let temperature = patch.targetTemperature {
            // Limits depend on the (possibly just changed) mode.
            let limits = device(conf: conf, state: next)
            let step = max(limits.targetTemperatureStep, 0.1)
            let rounded = (temperature / step).rounded() * step
            next["SetTemperature"] = .number(min(max(rounded, limits.targetTemperatureMin), limits.targetTemperatureMax))
            flags |= flagTemperature
        }
        if let speed = patch.fanSpeed {
            guard current.fanSpeeds.contains(speed) else { throw MappingError.unsupported("fan speed \(speed)") }
            next["SetFanSpeed"] = .number(speed == "auto" ? 0 : Double(Int(speed) ?? 0))
            flags |= flagFanSpeed
        }
        if let position = patch.vaneVertical {
            guard current.vaneVerticalPositions.contains(position),
                  let code = vaneCodes.first(where: { $0.value == position })?.key else {
                throw MappingError.unsupported("vane position \(position)")
            }
            next["VaneVertical"] = .number(Double(code))
            flags |= flagVaneVertical
        }

        next["EffectiveFlags"] = .number(Double(flags))
        next["HasPendingCommand"] = .bool(flags != 0)
        return next
    }

    // MARK: Capabilities

    private static func temperatureKeys(for mode: OperationMode) -> (String, String) {
        switch mode {
        case .dry, .cool: ("MinTempCoolDry", "MaxTempCoolDry")
        case .heatCool: ("MinTempAutomatic", "MaxTempAutomatic")
        case .heat, .fanOnly, .undefined: ("MinTempHeat", "MaxTempHeat")
        }
    }

    private static func operationModes(_ caps: JSONObject) -> [OperationMode] {
        var modes: [OperationMode] = []
        if caps["CanHeat"]?.bool == true { modes.append(.heat) }
        if caps["CanDry"]?.bool == true { modes.append(.dry) }
        if caps["CanCool"]?.bool == true { modes.append(.cool) }
        modes.append(.fanOnly)
        if caps["ModelSupportsAuto"]?.bool == true { modes.append(.heatCool) }
        return modes
    }

    private static func fanSpeeds(caps: JSONObject, state: JSONObject) -> [String] {
        var speeds: [String] = []
        if caps["HasAutomaticFanSpeed"]?.bool == true { speeds.append("auto") }
        let count = state["NumberOfFanSpeeds"]?.int ?? 0
        if count > 0 { speeds += (1...count).map(String.init) }
        return speeds
    }

    private static func vanePositions(conf: JSONObject, caps: JSONObject) -> [String] {
        // MELCloud swaps the vertical/horizontal capability flags; "Horizontal" means the up/down vane.
        guard conf["HideVaneControls"]?.bool != true, caps["ModelSupportsVaneHorizontal"]?.bool == true else { return [] }
        var positions = ["auto", "1_up", "2", "3", "4", "5_down"]
        if caps["SwingFunction"]?.bool == true { positions.append("swing") }
        return positions
    }
}
