import Foundation

/// UI-facing state of one indoor unit, built from MELCloud data by `AirToAirMapping`.
struct ACDevice: Equatable, Identifiable {
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
    var hasError: Bool
    var errorCode: String?

    /// 0 = coldest setpoint, 1 = warmest. Drives the dynamic colour theme.
    var warmth: Double {
        let span = targetTemperatureMax - targetTemperatureMin
        guard span > 0 else { return 0.5 }
        return min(max((targetTemperature - targetTemperatureMin) / span, 0), 1)
    }

    mutating func apply(_ patch: StatePatch) {
        if let v = patch.power { power = v }
        if let v = patch.targetTemperature { targetTemperature = v }
        if let v = patch.operationMode { operationMode = v }
        if let v = patch.fanSpeed { fanSpeed = v }
        if let v = patch.vaneVertical { vaneVertical = v }
    }
}

/// Entry of the device menu.
struct DeviceSummary: Identifiable, Equatable, Sendable {
    let id: Int
    let buildingID: Int
    let name: String
}

extension ACDevice {
    static let demo = ACDevice(
        id: 0, name: "Bedroom", power: true, roomTemperature: 25, outdoorTemperature: nil,
        targetTemperature: 21, targetTemperatureMin: 16, targetTemperatureMax: 31, targetTemperatureStep: 0.5,
        operationMode: .heat, operationModes: [.heat, .dry, .cool, .fanOnly, .heatCool],
        fanSpeed: "auto", fanSpeeds: ["auto", "1", "2", "3", "4", "5"],
        vaneVertical: "auto", vaneVerticalPositions: ["auto", "1_up", "2", "3", "4", "5_down", "swing"],
        hasError: false, errorCode: nil
    )
}

enum OperationMode: String, CaseIterable, Sendable {
    case heat, dry, cool
    case fanOnly = "fan_only"
    case heatCool = "heat_cool"
    case undefined

    var title: String {
        switch self {
        case .heat: "Heat"
        case .dry: "Dry"
        case .cool: "Cool"
        case .fanOnly: "Fan"
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

/// Partial update; nil fields stay unchanged.
struct StatePatch: Equatable, Sendable {
    var power: Bool?
    var targetTemperature: Double?
    var operationMode: OperationMode?
    var fanSpeed: String?
    var vaneVertical: String?

    var isEmpty: Bool { self == StatePatch() }

    /// Later values win, so rapid changes collapse into one request.
    func merged(with other: StatePatch) -> StatePatch {
        StatePatch(
            power: other.power ?? power,
            targetTemperature: other.targetTemperature ?? targetTemperature,
            operationMode: other.operationMode ?? operationMode,
            fanSpeed: other.fanSpeed ?? fanSpeed,
            vaneVertical: other.vaneVertical ?? vaneVertical
        )
    }
}

enum Labels {
    static func fanSpeed(_ value: String?) -> String {
        switch value {
        case nil: "–"
        case "auto": "Auto"
        case let v?: "Speed \(v)"
        }
    }

    static func vane(_ value: String?) -> String {
        switch value {
        case nil: "–"
        case "auto": "Auto"
        case "swing": "Swing"
        case "1_up": "Top"
        case "2": "Upper"
        case "3": "Middle"
        case "4": "Lower"
        case "5_down": "Bottom"
        case let v?: v
        }
    }
}
