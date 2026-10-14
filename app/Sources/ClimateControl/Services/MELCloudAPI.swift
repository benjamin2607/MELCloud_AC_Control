import Foundation

/// Thin HTTP layer for the (unofficial) MELCloud API used by the official app.
/// Endpoint usage, headers and field semantics follow python-melcloud (MIT), see NOTICE.
struct MELCloudAPI: Sendable {
    enum APIError: Error, Equatable {
        case invalidCredentials
        case unauthorized
        case http(status: Int)
        case unexpectedResponse
    }

    struct Login: Sendable {
        let token: String
        let expiry: Date?
    }

    private static let baseURL = URL(string: "https://app.melcloud.com/Mitsubishi.Wifi.Client/")!
    private let session: URLSession

    init() {
        // Ephemeral: no cookies, cache or credentials are written to disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func login(email: String, password: String) async throws -> Login {
        let body: JSONObject = [
            "Email": .string(email),
            "Password": .string(password),
            "Language": .number(0),
            "AppVersion": .string("1.19.1.1"),
            "Persist": .bool(true),
            "CaptchaResponse": .null,
        ]
        let response = try await send("Login/ClientLogin", method: "POST", token: nil, body: .object(body))
        // A failed login is answered with HTTP 200, an ErrorId and LoginData = null.
        guard let data = response.object?["LoginData"]?.object, let token = data["ContextKey"]?.string, !token.isEmpty else {
            throw APIError.invalidCredentials
        }
        let expiry = data["TokenExpiry"]?.string.flatMap(Self.parseDate)
        return Login(token: token, expiry: expiry)
    }

    /// All device configurations of the account, flattened across buildings, floors and areas.
    func listDevices(token: String) async throws -> [JSONObject] {
        let response = try await send("User/ListDevices", method: "GET", token: token)
        var devices: [JSONObject] = []
        for building in response.array ?? [] {
            guard let structure = building.object?["Structure"]?.object else { continue }
            devices += Self.devices(in: structure)
            for area in structure["Areas"]?.array ?? [] { devices += Self.devices(in: area.object) }
            for floor in structure["Floors"]?.array ?? [] {
                devices += Self.devices(in: floor.object)
                for area in floor.object?["Areas"]?.array ?? [] { devices += Self.devices(in: area.object) }
            }
        }
        var seen = Set<Int>()
        return devices.filter { device in
            guard let id = device["DeviceID"]?.int else { return false }
            return seen.insert(id).inserted
        }
    }

    func deviceState(token: String, deviceID: Int, buildingID: Int) async throws -> JSONObject {
        let response = try await send("Device/Get?id=\(deviceID)&buildingID=\(buildingID)", method: "GET", token: token)
        guard let state = response.object else { throw APIError.unexpectedResponse }
        return state
    }

    /// Writes an air-to-air state. The state must carry EffectiveFlags for the changed fields.
    func setAirToAir(token: String, state: JSONObject) async throws -> JSONObject {
        let response = try await send("Device/SetAta", method: "POST", token: token, body: .object(state))
        guard let state = response.object else { throw APIError.unexpectedResponse }
        return state
    }

    // MARK: Private

    private static func devices(in container: JSONObject?) -> [JSONObject] {
        (container?["Devices"]?.array ?? []).compactMap(\.object)
    }

    private func send(_ path: String, method: String, token: String?, body: JSONValue? = nil) async throws -> JSONValue {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.unexpectedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Same headers as the web client / python-melcloud; MELCloud is picky about them.
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("policyaccepted=true", forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (X11; Linux x86_64; rv:73.0) Gecko/20100101 Firefox/73.0",
            forHTTPHeaderField: "User-Agent"
        )
        if let token { request.setValue(token, forHTTPHeaderField: "X-MitsContextKey") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.unexpectedResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw APIError.unauthorized
        default: throw APIError.http(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw APIError.unexpectedResponse
        }
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
