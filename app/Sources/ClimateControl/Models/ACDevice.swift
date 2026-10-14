import Foundation

/// Device state as delivered by the local bridge (see docs/API.md).
struct ACDevice: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var power: Bool
    var roomTemperature: Double?
    var outdoorTemperature: Double?
    var targetTemperature: Double
    var targetTemperatureMin: Double
    var targetTemperatureMax: Double
    var targetTemperatureStep: Double
    var operationMode: OperationMode
    var operationModes: [OperationMode]
    var fanSpeed: String?
    var fanSpeeds: [String]
    var vaneVertical: String?
    var vaneVerticalPositions: [String]
    var vaneHorizontal: String?
    var vaneHorizontalPositions: [String]
    var hasError: Bool
    var errorCode: String?

    /// 0 = coldest setpoint, 1 = warmest. Drives the dynamic colour theme.
    var warmth: Double {
        let span = targetTemperatureMax - targetTemperatureMin
        guard span > 0 else { return 0.5 }
        return min(max((targetTemperature - targetTemperatureMin) / span, 0), 1)
    }

    /// Modes offered in the UI, limited to what the unit supports.
    var selectableModes: [OperationMode] { OperationMode.selectable.filter(operationModes.contains) }

    mutating func apply(_ patch: StatePatch) {
        if let v = patch.power { power = v }
        if let v = patch.targetTemperature { targetTemperature = v }
        if let v = patch.operationMode { operationMode = v }
        if let v = patch.fanSpeed { fanSpeed = v }
        if let v = patch.vaneVertical { vaneVertical = v }
        if let v = patch.vaneHorizontal { vaneHorizontal = v }
    }
}

extension ACDevice {
    static let demo = ACDevice(
        id: 0, name: "Schlafzimmer", power: true, roomTemperature: 25, outdoorTemperature: nil,
        targetTemperature: 21, targetTemperatureMin: 16, targetTemperatureMax: 31, targetTemperatureStep: 0.5,
        operationMode: .heat, operationModes: [.heat, .dry, .cool, .fanOnly, .heatCool],
        fanSpeed: "auto", fanSpeeds: ["auto", "1", "2", "3", "4", "5"],
        vaneVertical: "auto", vaneVerticalPositions: ["auto", "1_up", "2", "3", "4", "5_down", "swing"],
        vaneHorizontal: nil, vaneHorizontalPositions: [], hasError: false, errorCode: nil
    )
}

enum OperationMode: String, Codable, CaseIterable {
    case heat, dry, cool
    case fanOnly = "fan_only"
    case heatCool = "heat_cool"
    case undefined

    /// Only these are offered in the UI (no cooling/drying in this setup).
    static let selectable: [OperationMode] = [.heat, .fanOnly, .heatCool]

    init(from decoder: Decoder) throws {
        self = OperationMode(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .undefined
    }

    var title: String {
        switch self {
        case .heat: "Heizen"
        case .dry: "Entfeuchten"
        case .cool: "Kühlen"
        case .fanOnly: "Lüften"
        case .heatCool: "Auto"
        case .undefined: "–"
        }
    }

    var symbol: String {
        switch self {
        case .heat: "sun.max.fill"
        case .dry: "drop.fill"
        case .cool: "snowflake"
        case .fanOnly: "fan.fill"
        case .heatCool: "arrow.triangle.2.circlepath"
        case .undefined: "questionmark"
        }
    }
}

/// Partial update sent to the bridge. nil fields are omitted from the JSON.
struct StatePatch: Codable, Equatable {
    var power: Bool?
    var targetTemperature: Double?
    var operationMode: OperationMode?
    var fanSpeed: String?
    var vaneVertical: String?
    var vaneHorizontal: String?

    var isEmpty: Bool { self == StatePatch() }

    /// Later values win, so rapid slider moves collapse into one request.
    func merged(with other: StatePatch) -> StatePatch {
        StatePatch(
            power: other.power ?? power,
            targetTemperature: other.targetTemperature ?? targetTemperature,
            operationMode: other.operationMode ?? operationMode,
            fanSpeed: other.fanSpeed ?? fanSpeed,
            vaneVertical: other.vaneVertical ?? vaneVertical,
            vaneHorizontal: other.vaneHorizontal ?? vaneHorizontal
        )
    }
}

enum Labels {
    static func fanSpeed(_ value: String?) -> String {
        switch value {
        case nil: "–"
        case "auto": "Auto"
        case let v?: "Stufe \(v)"
        }
    }

    static func vane(_ value: String?) -> String {
        switch value {
        case nil: "–"
        case "auto": "Auto"
        case "swing": "Swing"
        case "1_up": "Oben"
        case "2": "Halb oben"
        case "3": "Mitte"
        case "4": "Halb unten"
        case "5_down": "Unten"
        case let v?: v
        }
    }
}
