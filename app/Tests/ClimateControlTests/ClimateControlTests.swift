import Foundation
import Testing
@testable import ClimateControl

/// Trimmed-down MELCloud payloads (shape as returned by User/ListDevices and Device/Get).
enum Fixtures {
    static let conf: JSONObject = [
        "DeviceID": .number(101),
        "BuildingID": .number(7),
        "DeviceName": .string("Bedroom"),
        "Device": .object([
            "DeviceType": .number(0),
            "CanHeat": .bool(true),
            "CanCool": .bool(true),
            "CanDry": .bool(true),
            "ModelSupportsAuto": .bool(true),
            "HasAutomaticFanSpeed": .bool(true),
            "ModelSupportsVaneHorizontal": .bool(true),
            "ModelSupportsVaneVertical": .bool(true),
            "SwingFunction": .bool(true),
            "MinTempHeat": .number(10),
            "MaxTempHeat": .number(31),
            "MinTempCoolDry": .number(16),
            "MaxTempCoolDry": .number(31),
            "TemperatureIncrement": .number(0.5),
        ]),
    ]

    static let state: JSONObject = [
        "DeviceID": .number(101),
        "DeviceType": .number(0),
        "Power": .bool(false),
        "RoomTemperature": .number(24),
        "SetTemperature": .number(24),
        "OperationMode": .number(1),
        "SetFanSpeed": .number(4),
        "NumberOfFanSpeeds": .number(5),
        "VaneVertical": .number(4),
        "VaneHorizontal": .number(3),
        "HasError": .bool(false),
        "ErrorCode": .number(8000),
        "EffectiveFlags": .number(0),
    ]
}

@Test func mapsStateAndCapabilities() {
    let device = AirToAirMapping.device(conf: Fixtures.conf, state: Fixtures.state)
    #expect(device.id == 101)
    #expect(device.operationMode == .heat)
    #expect(device.operationModes == [.heat, .dry, .cool, .fanOnly, .heatCool])
    #expect(device.targetTemperatureMin == 10) // heat mode limits
    #expect(device.fanSpeed == "4")
    #expect(device.fanSpeeds == ["auto", "1", "2", "3", "4", "5"])
    #expect(device.vaneVertical == "4")
    #expect(device.vaneVerticalPositions.last == "swing")
    #expect(device.errorCode == nil) // 8000 means "no error"
    #expect(device.vaneHorizontal == "3")
    #expect(device.vaneHorizontalPositions == ["auto", "1_left", "2", "3", "4", "5_right", "split", "swing"])
}

@Test func applyHorizontalVane() throws {
    let next = try AirToAirMapping.apply(StatePatch(vaneHorizontal: "split"), to: Fixtures.state, conf: Fixtures.conf)
    #expect(next["VaneHorizontal"] == .number(8))
    #expect(next["EffectiveFlags"] == .number(Double(0x100)))
}

@Test func fahrenheitDisplay() {
    #expect(TemperatureUnit.fahrenheit.format(21) == "70")   // 69.8 °F
    #expect(TemperatureUnit.fahrenheit.format(16) == "61")   // 60.8 °F
    #expect(TemperatureUnit.celsius.symbol == "°C")
}

@Test func versionComparison() {
    #expect(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.2"))
    #expect(UpdateChecker.isVersion("1.0.1", newerThan: "1.0"))
    #expect(!UpdateChecker.isVersion("1.0.0", newerThan: "1.0.0"))
    #expect(!UpdateChecker.isVersion("0.9", newerThan: "1.0.0"))
}

@Test func applySetsValuesAndFlags() throws {
    let patch = StatePatch(power: true, targetTemperature: 21.3, fanSpeed: "auto", vaneVertical: "swing")
    let next = try AirToAirMapping.apply(patch, to: Fixtures.state, conf: Fixtures.conf)
    #expect(next["Power"] == .bool(true))
    #expect(next["SetTemperature"] == .number(21.5))
    #expect(next["SetFanSpeed"] == .number(0))
    #expect(next["VaneVertical"] == .number(7))
    #expect(next["EffectiveFlags"] == .number(Double(0x01 | 0x04 | 0x08 | 0x10)))
    #expect(next["VaneHorizontal"] == .number(3)) // untouched fields survive
}

@Test func temperatureIsClampedToModeLimits() throws {
    // Switching to cool raises the minimum from 10 to 16 °C.
    let patch = StatePatch(targetTemperature: 12, operationMode: .cool)
    let next = try AirToAirMapping.apply(patch, to: Fixtures.state, conf: Fixtures.conf)
    #expect(next["OperationMode"] == .number(3))
    #expect(next["SetTemperature"] == .number(16))
}

@Test func rejectsUnsupportedValues() {
    #expect(throws: AirToAirMapping.MappingError.self) {
        try AirToAirMapping.apply(StatePatch(fanSpeed: "9"), to: Fixtures.state, conf: Fixtures.conf)
    }
}

@Test func jsonRoundTripKeepsIntegersIntegral() throws {
    let data = try JSONEncoder().encode(JSONValue.object(["EffectiveFlags": .number(7), "T": .number(21.5)]))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"EffectiveFlags\":7"))
    #expect(text.contains("21.5"))
}

@Test func patchMergeKeepsLatestValues() {
    let merged = StatePatch(power: true, targetTemperature: 20)
        .merged(with: StatePatch(targetTemperature: 22.5))
    #expect(merged == StatePatch(power: true, targetTemperature: 22.5))
}

@Test func colorLerpClamps() {
    let a = RGB(0, 0, 0), b = RGB(1, 1, 1)
    #expect(a.lerp(b, 0.5) == RGB(0.5, 0.5, 0.5))
    #expect(a.lerp(b, 2) == b)
}
