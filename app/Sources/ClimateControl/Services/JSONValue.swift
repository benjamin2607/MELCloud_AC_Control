import Foundation

/// Minimal lossless JSON model. MELCloud expects the full device state to be posted back when writing,
/// so unknown fields must survive a decode/encode round trip untouched.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Keep integers integral (IDs, flags, enum codes); MELCloud rejects 7.0 where it expects 7.
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    var double: Double? { if case .number(let v) = self { v } else { nil } }
    var int: Int? { double.map { Int($0) } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    var object: JSONObject? { if case .object(let v) = self { v } else { nil } }
}

typealias JSONObject = [String: JSONValue]
