import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let displayName: String?
}

struct AuthResponse: Codable, Equatable, Sendable {
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct AuthTokenResponse: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

enum AuthErrorCode: String, Codable, Equatable, Sendable {
    case validationError = "VALIDATION_ERROR"
    case unauthorized = "UNAUTHORIZED"
    case tokenExpired = "TOKEN_EXPIRED"
    case emailTaken = "EMAIL_TAKEN"
    case rateLimited = "RATE_LIMITED"
    case serviceUnavailable = "SERVICE_UNAVAILABLE"
    case internalError = "INTERNAL_ERROR"
}

enum AuthError: LocalizedError, Equatable, Sendable {
    case backend(code: AuthErrorCode, message: String, requestID: String?, retryAfter: Int?)
    case validation(message: String)
    case unauthorized(message: String)
    case tokenExpired(message: String)
    case emailTaken(message: String)
    case rateLimited(message: String, retryAfter: Int?)
    case serviceUnavailable(message: String)
    case internalError(message: String)
    case offline
    case serverUnavailable
    case invalidResponse
    case decodingError
    case keychain(message: String)

    var code: AuthErrorCode? {
        switch self {
        case let .backend(code, _, _, _): return code
        case .validation: return .validationError
        case .unauthorized: return .unauthorized
        case .tokenExpired: return .tokenExpired
        case .emailTaken: return .emailTaken
        case .rateLimited: return .rateLimited
        case .serviceUnavailable: return .serviceUnavailable
        case .internalError: return .internalError
        case .offline, .serverUnavailable, .invalidResponse, .decodingError, .keychain: return nil
        }
    }

    var requestID: String? {
        if case let .backend(_, _, requestID, _) = self { return requestID }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case let .backend(code, message, _, retryAfter):
            if code == .rateLimited, let retryAfter {
                let minutes = max(1, Int(ceil(Double(retryAfter) / 60)))
                return "Too many attempts. Try again in about \(minutes) \(minutes == 1 ? "minute" : "minutes")."
            }
            return message
        case let .validation(message), let .unauthorized(message), let .tokenExpired(message),
             let .emailTaken(message), let .serviceUnavailable(message), let .internalError(message):
            return message
        case let .rateLimited(message, retryAfter):
            if let retryAfter {
                let minutes = max(1, Int(ceil(Double(retryAfter) / 60)))
                let unit = minutes == 1 ? "minute" : "minutes"
                return "Too many attempts. Try again in about " + String(minutes) + " " + unit + "."
            }
            return message
        case .offline:
            return "Working offline. Check your connection and try again when you are back online."
        case .serverUnavailable:
            return "Roam is having trouble right now. Try again soon."
        case .invalidResponse, .decodingError:
            return "Roam could not read the server response. Try again soon."
        case let .keychain(message):
            return message
        }
    }

    var isTransient: Bool {
        switch self {
        case let .backend(code, _, _, _):
            return [.rateLimited, .serviceUnavailable].contains(code)
        case .offline, .serverUnavailable, .serviceUnavailable, .rateLimited:
            return true
        default:
            return false
        }
    }

    static func from(statusCode: Int, data: Data, retryAfter: Int? = nil) -> AuthError {
        struct ErrorEnvelope: Decodable {
            let error: String?
            let code: AuthErrorCode?
            let requestId: String?
        }

        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let message = envelope?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMessage = message.flatMap { $0.isEmpty ? nil : $0 }
        let code = envelope?.code ?? fallbackCode(for: statusCode)
        let text = safeMessage ?? defaultMessage(for: code)
        return .backend(code: code, message: text, requestID: envelope?.requestId, retryAfter: retryAfter)
    }

    private static func fallbackCode(for statusCode: Int) -> AuthErrorCode {
        switch statusCode {
        case 400: return .validationError
        case 401: return .unauthorized
        case 409: return .emailTaken
        case 429: return .rateLimited
        case 503: return .serviceUnavailable
        default: return .internalError
        }
    }

    private static func defaultMessage(for code: AuthErrorCode) -> String {
        switch code {
        case .validationError: return "Check the details and try again."
        case .unauthorized: return "That sign-in did not work. Check your details and try again."
        case .tokenExpired: return "Your session has expired. Please sign in again."
        case .emailTaken: return "That email is already in use."
        case .rateLimited: return "Too many attempts. Try again soon."
        case .serviceUnavailable: return "Roam is unavailable right now. Try again soon."
        case .internalError: return "Something went wrong on Roam's side. Try again soon."
        }
    }
}

enum HealthStatus: String, Codable, Equatable, Sendable {
    case ok
    case degraded
}

enum DatabaseStatus: String, Codable, Equatable, Sendable {
    case up
    case down
    case unconfigured
}

struct HealthResponse: Codable, Equatable, Sendable {
    let status: HealthStatus
    let database: DatabaseStatus
    let version: String
}

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

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
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct RemoteProfile: Codable, Equatable, Sendable {
    let displayName: String
    let stage: DriverProfile.Stage
    let payload: [String: JSONValue]
    let updatedAt: Date

    init(displayName: String, stage: DriverProfile.Stage, payload: [String: JSONValue], updatedAt: Date) {
        self.displayName = displayName
        self.stage = stage
        self.payload = payload
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, stage, payload, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        stage = try container.decode(DriverProfile.Stage.self, forKey: .stage)
        payload = try container.decodeIfPresent([String: JSONValue].self, forKey: .payload) ?? [:]
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

protocol AuthServicing: Sendable {
    func signUp(email: String, password: String, displayName: String?) async throws -> AuthResponse
    func login(email: String, password: String) async throws -> AuthResponse
    func refresh(refreshToken: String) async throws -> AuthTokenResponse
    func logout(refreshToken: String) async throws
    func currentUser(accessToken: String) async throws -> AuthUser
    func profile(accessToken: String) async throws -> RemoteProfile
    func updateProfile(accessToken: String, displayName: String?, stage: DriverProfile.Stage?, payload: [String: JSONValue]?) async throws -> RemoteProfile
    func deleteAccount(accessToken: String) async throws
    func health() async throws -> HealthResponse
}

struct AuthClient: AuthServicing, Sendable {
    private let apiClient: APIClient

    init(
        candidateBaseURLs: [URL] = AppConfiguration.candidateBaseURLs,
        session: URLSession = .shared
    ) {
        apiClient = APIClient(candidateBaseURLs: candidateBaseURLs, session: session)
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthResponse {
        let body = SignUpRequest(email: email, password: password, displayName: displayName)
        return try await request(path: "api/auth/signup", method: "POST", body: body)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password)
        return try await request(path: "api/auth/login", method: "POST", body: body)
    }

    func refresh(refreshToken: String) async throws -> AuthTokenResponse {
        return try await request(path: "api/auth/refresh", method: "POST", body: RefreshRequest(refreshToken: refreshToken))
    }

    func logout(refreshToken: String) async throws {
        try await requestNoContent(path: "api/auth/logout", method: "POST", body: RefreshRequest(refreshToken: refreshToken))
    }

    func currentUser(accessToken: String) async throws -> AuthUser {
        let response: MeResponse = try await request(path: "api/auth/me", method: "GET", accessToken: accessToken)
        return response.user
    }

    func profile(accessToken: String) async throws -> RemoteProfile {
        let response: ProfileResponse = try await request(path: "api/profile", method: "GET", accessToken: accessToken)
        return response.profile
    }

    func updateProfile(accessToken: String, displayName: String?, stage: DriverProfile.Stage?, payload: [String: JSONValue]?) async throws -> RemoteProfile {
        let body = ProfileUpdateRequest(displayName: displayName, stage: stage, payload: payload)
        let response: ProfileResponse = try await request(path: "api/profile", method: "PUT", body: body, accessToken: accessToken)
        return response.profile
    }

    func deleteAccount(accessToken: String) async throws {
        try await requestNoContent(path: "api/account", method: "DELETE", body: Optional<EmptyBody>.none, accessToken: accessToken)
    }

    func health() async throws -> HealthResponse {
        try await request(path: "health", method: "GET")
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body? = nil,
        accessToken: String? = nil
    ) async throws -> Response {
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        let response = try await send(path: path, method: method, body: encodedBody, accessToken: accessToken)
        guard (200...299).contains(response.response.statusCode) else {
            throw Self.authError(from: response)
        }
        do {
            return try makeDecoder().decode(Response.self, from: response.data)
        } catch {
            throw AuthError.decodingError
        }
    }

    private func request<Response: Decodable>(path: String, method: String, accessToken: String? = nil) async throws -> Response {
        try await request(path: path, method: method, body: Optional<EmptyBody>.none, accessToken: accessToken)
    }

    private func requestNoContent<Body: Encodable>(path: String, method: String, body: Body? = nil, accessToken: String? = nil) async throws {
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        let response = try await send(path: path, method: method, body: encodedBody, accessToken: accessToken)
        guard (200...299).contains(response.response.statusCode) else {
            throw Self.authError(from: response)
        }
    }

    private func send(path: String, method: String, body: Data?, accessToken: String?) async throws -> APIClient.HTTPResponseData {
        var headers = ["Content-Type": "application/json"]
        if let accessToken {
            headers["Authorization"] = "Bearer " + accessToken
        }
        do {
            return try await apiClient.requestData(path: path, method: method, body: body, headers: headers)
        } catch APIError.networkError {
            throw AuthError.offline
        } catch APIError.invalidResponse {
            throw AuthError.serverUnavailable
        } catch APIError.invalidURL {
            throw AuthError.serverUnavailable
        } catch {
            throw AuthError.serverUnavailable
        }
    }

    private static func authError(from response: APIClient.HTTPResponseData) -> AuthError {
        let retryAfter = response.response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        return AuthError.from(statusCode: response.response.statusCode, data: response.data, retryAfter: retryAfter)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid server date")
            }
            return date
        }
        return decoder
    }
}

private struct SignUpRequest: Encodable {
    let email: String
    let password: String
    let displayName: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encode(password, forKey: .password)
        try container.encodeIfPresent(displayName, forKey: .displayName)
    }

    private enum CodingKeys: String, CodingKey {
        case email, password, displayName
    }
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct ProfileUpdateRequest: Encodable {
    let displayName: String?
    let stage: DriverProfile.Stage?
    let payload: [String: JSONValue]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(stage, forKey: .stage)
        try container.encodeIfPresent(payload, forKey: .payload)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, stage, payload
    }
}

private struct EmptyBody: Encodable {}

private struct MeResponse: Decodable {
    let user: AuthUser
}

private struct ProfileResponse: Decodable {
    let profile: RemoteProfile
}
