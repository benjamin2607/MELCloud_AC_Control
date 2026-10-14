import Foundation

/// Owns the MELCloud session: token handling, caching and rate limiting.
/// MELCloud throttles accounts that poll too often, so device lists and states are cached.
actor MELCloudService {
    enum ServiceError: LocalizedError, Equatable {
        case notSignedIn
        case invalidCredentials
        case sessionExpired
        case deviceNotFound
        case unsupported(String)
        case server(Int)
        case offline
        case unexpectedResponse
        case keychainUnavailable

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Not signed in."
            case .invalidCredentials: "Sign-in failed. Check email and password."
            case .sessionExpired: "Session expired. Please sign in again."
            case .deviceNotFound: "Device not found in MELCloud."
            case .unsupported(let what): "Not supported by this unit: \(what)."
            case .server(let status): "MELCloud error (HTTP \(status))."
            case .offline: "MELCloud is not reachable."
            case .unexpectedResponse: "Unexpected response from MELCloud."
            case .keychainUnavailable: "Could not save the session to the Keychain."
            }
        }
    }

    private let api = MELCloudAPI()
    private let credentials = CredentialStore()
    private let confTTL: TimeInterval = 300
    private let stateTTL: TimeInterval = 30

    private var confs: [Int: JSONObject] = [:]
    private var confOrder: [Int] = []
    private var confsFetchedAt: Date?
    private var states: [Int: (state: JSONObject, fetchedAt: Date)] = [:]

    nonisolated var isSignedIn: Bool { credentials.token() != nil }
    nonisolated var accountEmail: String? { credentials.email }

    // MARK: Session

    func signIn(email: String, password: String) async throws {
        do {
            let login = try await api.login(email: email, password: password)
            guard credentials.save(token: login.token, email: email) else { throw ServiceError.keychainUnavailable }
            resetCaches()
        } catch {
            throw Self.map(error)
        }
    }

    func signOut() {
        credentials.clearAll()
        resetCaches()
    }

    // MARK: Devices

    func devices() async throws -> [DeviceSummary] {
        try await loadConfs(force: false)
        return confOrder.compactMap { confs[$0].flatMap(AirToAirMapping.summary) }
    }

    func device(id: Int, force: Bool = false) async throws -> ACDevice {
        let conf = try await conf(for: id)
        let state = try await state(for: id, conf: conf, force: force)
        return AirToAirMapping.device(conf: conf, state: state)
    }

    func apply(_ patch: StatePatch, to id: Int) async throws -> ACDevice {
        let conf = try await conf(for: id)
        let current = try await state(for: id, conf: conf, force: false)
        let next: JSONObject
        do {
            next = try AirToAirMapping.apply(patch, to: current, conf: conf)
        } catch AirToAirMapping.MappingError.unsupported(let what) {
            throw ServiceError.unsupported(what)
        }
        let written = try await authorized { token in try await self.api.setAirToAir(token: token, state: next) }
        // SetAta answers with the accepted state; merge so fields it omits stay intact.
        let merged = current.merging(written) { _, new in new }
        states[id] = (merged, Date())
        return AirToAirMapping.device(conf: conf, state: merged)
    }

    // MARK: Private

    private func conf(for id: Int) async throws -> JSONObject {
        try await loadConfs(force: false)
        if confs[id] == nil { try await loadConfs(force: true) }
        guard let conf = confs[id] else { throw ServiceError.deviceNotFound }
        return conf
    }

    private func loadConfs(force: Bool) async throws {
        if !force, let fetched = confsFetchedAt, Date().timeIntervalSince(fetched) < confTTL { return }
        let all = try await authorized { token in try await self.api.listDevices(token: token) }
        let airToAir = all.filter(AirToAirMapping.isAirToAir)
        confs = Dictionary(airToAir.compactMap { conf in conf["DeviceID"]?.int.map { ($0, conf) } }) { first, _ in first }
        confOrder = airToAir.compactMap { $0["DeviceID"]?.int }
        confsFetchedAt = Date()
    }

    private func state(for id: Int, conf: JSONObject, force: Bool) async throws -> JSONObject {
        if !force, let cached = states[id], Date().timeIntervalSince(cached.fetchedAt) < stateTTL { return cached.state }
        guard let buildingID = conf["BuildingID"]?.int else { throw ServiceError.unexpectedResponse }
        let state = try await authorized { token in
            try await self.api.deviceState(token: token, deviceID: id, buildingID: buildingID)
        }
        states[id] = (state, Date())
        return state
    }

    private func authorized<T: Sendable>(_ operation: @Sendable (String) async throws -> T) async throws -> T {
        guard let token = credentials.token() else { throw ServiceError.notSignedIn }
        do {
            return try await operation(token)
        } catch MELCloudAPI.APIError.unauthorized {
            credentials.clearToken()
            resetCaches()
            throw ServiceError.sessionExpired
        } catch {
            throw Self.map(error)
        }
    }

    private func resetCaches() {
        confs = [:]
        confOrder = []
        confsFetchedAt = nil
        states = [:]
    }

    private static func map(_ error: Error) -> Error {
        switch error {
        case let error as ServiceError: error
        case MELCloudAPI.APIError.invalidCredentials: ServiceError.invalidCredentials
        case MELCloudAPI.APIError.unauthorized: ServiceError.sessionExpired
        case MELCloudAPI.APIError.http(let status): ServiceError.server(status)
        case MELCloudAPI.APIError.unexpectedResponse: ServiceError.unexpectedResponse
        case is URLError: ServiceError.offline
        default: error
        }
    }
}
