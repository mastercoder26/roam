import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL configuration."
        case .invalidResponse:
            return "Unexpected server response."
        case .httpError(let code, let message):
            if let message, !message.isEmpty {
                return "Server error (\(code)): \(message)"
            }
            return "Server error (\(code))."
        case .decodingError:
            return "Could not read route data from the server."
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}

struct APIClient {
    let baseURL: URL
    private let fallbackBaseURL: URL?
    private let session: URLSession

    init(
        baseURL: URL? = nil,
        fallbackBaseURL: URL? = AppConfiguration.fallbackAPIBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? AppConfiguration.apiBaseURL
        self.fallbackBaseURL = fallbackBaseURL
        self.session = session
    }

    func analyzeRoute(
        origin: String,
        destination: String,
        departureTime: Date,
        includeAlternates: Bool = true,
        continuousDriveMinutes: Double? = nil
    ) async throws -> RouteDifficultyResponse {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let localTime = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: departureTime)
        let departureLocalMinutes = (localTime.hour ?? 0) * 60 + (localTime.minute ?? 0)

        let body = RouteDifficultyRequest(
            origin: origin.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            departureTime: formatter.string(from: departureTime),
            departureLocalMinutes: departureLocalMinutes,
            includeAlternates: includeAlternates,
            continuousDriveMinutes: continuousDriveMinutes
        )

        let requestBody = try JSONEncoder().encode(body)

        do {
            return try await sendRouteRequest(to: baseURL, body: requestBody)
        } catch APIError.networkError(let networkError) {
            // A physical phone cannot reach the Mac through `localhost`, so try
            // the current development machine's LAN address after that fails.
            guard let fallbackBaseURL, fallbackBaseURL != baseURL else {
                throw APIError.networkError(networkError)
            }
            return try await sendRouteRequest(to: fallbackBaseURL, body: requestBody)
        }
    }

    private func sendRouteRequest(to baseURL: URL, body: Data) async throws -> RouteDifficultyResponse {
        let endpoint = baseURL.appendingPathComponent("api/route/difficulty")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = body

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(from: data)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(RouteDifficultyResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            let error: String?
            let message: String?
        }
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return body.error ?? body.message
    }
}

enum AppConfiguration {
    static var fallbackAPIBaseURL: URL? {
        configuredURL(forInfoDictionaryKey: "API_FALLBACK_BASE_URL")
    }

    static var apiBaseURL: URL {
        configuredURL(forInfoDictionaryKey: "API_BASE_URL")
            ?? URL(string: "http://localhost:3000")!
    }

    private static func configuredURL(forInfoDictionaryKey key: String) -> URL? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$") else {
            return nil
        }
        return URL(string: trimmed)
    }
}
