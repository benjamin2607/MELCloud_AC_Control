import Foundation

/// Talks to the local Python bridge (bridge/). All MELCloud specifics live there.
struct BridgeClient: Sendable {
    struct DeviceSummary: Decodable, Identifiable, Equatable {
        let id: Int
        let name: String
        /// Set by the bridge when the unit matches MELCLOUD_DEVICE in bridge/.env.
        var isDefault = false

        private enum CodingKeys: String, CodingKey { case id, name, isDefault = "default" }

        init(id: Int, name: String, isDefault: Bool = false) {
            (self.id, self.name, self.isDefault) = (id, name, isDefault)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        }
    }

    var baseURL = URL(string: "http://127.0.0.1:8765")!
    var session: URLSession = .shared

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func devices() async throws -> [DeviceSummary] {
        try await send(URLRequest(url: baseURL.appending(path: "devices")))
    }

    func state(deviceID: Int, force: Bool = false) async throws -> ACDevice {
        var url = baseURL.appending(path: "devices/\(deviceID)/state")
        if force { url.append(queryItems: [URLQueryItem(name: "force", value: "1")]) }
        return try await send(URLRequest(url: url))
    }

    func patch(deviceID: Int, _ patch: StatePatch) async throws -> ACDevice {
        var request = URLRequest(url: baseURL.appending(path: "devices/\(deviceID)/state"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(patch)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
