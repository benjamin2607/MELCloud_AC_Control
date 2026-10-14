import Foundation
import Testing
@testable import ClimateControl

@Test func patchMergeKeepsLatestValues() {
    let merged = StatePatch(power: true, targetTemperature: 20)
        .merged(with: StatePatch(targetTemperature: 22.5))
    #expect(merged == StatePatch(power: true, targetTemperature: 22.5))
}

@Test func decodesBridgeJSON() throws {
    let json = """
    {"id": 1, "name": "Schlafzimmer", "power": true, "room_temperature": 25.0, "outdoor_temperature": null,
     "target_temperature": 16, "target_temperature_min": 16, "target_temperature_max": 31,
     "target_temperature_step": 0.5, "operation_mode": "cool", "operation_modes": ["heat", "cool", "fan_only"],
     "fan_speed": "auto", "fan_speeds": ["auto", "1", "2"], "vane_vertical": "swing",
     "vane_vertical_positions": ["auto", "swing"], "vane_horizontal": null, "vane_horizontal_positions": [],
     "wifi_signal": -60, "has_error": false, "error_code": null, "last_seen": null}
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let device = try decoder.decode(ACDevice.self, from: Data(json.utf8))
    #expect(device.operationModes == [.heat, .cool, .fanOnly])
    #expect(device.warmth == 0)
}

@Test func colorLerpClamps() {
    let a = RGB(0, 0, 0), b = RGB(1, 1, 1)
    #expect(a.lerp(b, 0.5) == RGB(0.5, 0.5, 0.5))
    #expect(a.lerp(b, 2) == b)
}
