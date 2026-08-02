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
    /// Tried in order until one responds. See AppConfiguration.candidateBaseURLs.
    private let candidateBaseURLs: [URL]
    private let session: URLSession

    init(
        candidateBaseURLs: [URL] = AppConfiguration.candidateBaseURLs,
        session: URLSession = .shared
    ) {
        self.candidateBaseURLs = candidateBaseURLs
        self.session = session
    }

    func analyzeRoute(
        origin: String,
        destination: String,
        departureTime: Date,
        includeAlternates: Bool = true,
        continuousDriveMinutes: Double? = nil
    ) async throws -> RouteDifficultyResponse {
        try await analyzeRoute(
            origin: .address(origin.trimmingCharacters(in: .whitespacesAndNewlines)),
            destination: .address(destination.trimmingCharacters(in: .whitespacesAndNewlines)),
            departureTime: departureTime,
            includeAlternates: includeAlternates,
            continuousDriveMinutes: continuousDriveMinutes
        )
    }

    /// Uses the measured endpoints of a completed local drive. The server
    /// receives coordinates as native route waypoints, never as display text.
    func analyzeRoute(
        origin: RouteCoordinateEndpoint,
        destination: RouteCoordinateEndpoint,
        departureTime: Date,
        includeAlternates: Bool = false,
        continuousDriveMinutes: Double? = nil
    ) async throws -> RouteDifficultyResponse {
        try await analyzeRoute(
            origin: .coordinate(origin),
            destination: .coordinate(destination),
            departureTime: departureTime,
            includeAlternates: includeAlternates,
            continuousDriveMinutes: continuousDriveMinutes
        )
    }

    private func analyzeRoute(
        origin: RouteRequestEndpoint,
        destination: RouteRequestEndpoint,
        departureTime: Date,
        includeAlternates: Bool,
        continuousDriveMinutes: Double?
    ) async throws -> RouteDifficultyResponse {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let localTime = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: departureTime)
        let departureLocalMinutes = (localTime.hour ?? 0) * 60 + (localTime.minute ?? 0)

        let body = RouteDifficultyRequest(
            origin: origin,
            destination: destination,
            departureTime: formatter.string(from: departureTime),
            departureLocalMinutes: departureLocalMinutes,
            includeAlternates: includeAlternates,
            continuousDriveMinutes: continuousDriveMinutes
        )

        let requestBody = try JSONEncoder().encode(body)

        return try await sendWithFallback(
            path: "api/route/difficulty",
            body: requestBody,
            responseType: RouteDifficultyResponse.self
        )
    }

    /// Compares only route conditions for a small set of departure windows.
    /// The local readiness profile is intentionally not sent to the backend.
    func compareDepartureTimes(
        origin: String,
        destination: String,
        selectedDeparture: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> DepartureComparisonResponse {
        let candidates = DepartureComparisonWindowBuilder.makeCandidates(
            selectedDeparture: selectedDeparture,
            now: now,
            calendar: calendar
        )
        return try await compareDepartureTimes(
            origin: origin,
            destination: destination,
            candidates: candidates
        )
    }

    func compareDepartureTimes(
        origin: String,
        destination: String,
        candidates: [DepartureComparisonCandidate]
    ) async throws -> DepartureComparisonResponse {
        let body = DepartureComparisonRequest(
            origin: origin.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            candidates: candidates
        )
        let requestBody = try JSONEncoder().encode(body)

        return try await sendWithFallback(
            path: "api/route/departure-comparison",
            body: requestBody,
            responseType: DepartureComparisonResponse.self
        )
    }

    /// Tries each candidate base URL in order, only moving to the next one on
    /// a network failure (an HTTP error or bad response means that host is
    /// reachable, so it's the final answer, not a reason to try another).
    private func sendWithFallback<Response: Decodable>(
        path: String,
        body: Data,
        responseType: Response.Type
    ) async throws -> Response {
        var lastNetworkError: Error = URLError(.cannotConnectToHost)

        for baseURL in candidateBaseURLs {
            do {
                return try await sendRequest(to: baseURL, path: path, body: body, responseType: responseType)
            } catch APIError.networkError(let error) {
                lastNetworkError = error
            }
        }

        throw APIError.networkError(lastNetworkError)
    }

    private func sendRequest<Response: Decodable>(
        to baseURL: URL,
        path: String,
        body: Data,
        responseType: Response.Type
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent(path)

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
            return try decoder.decode(Response.self, from: data)
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
    private static let localhostBaseURL = URL(string: "http://localhost:3000")!

    /// The deployed backend (if configured), then localhost, then a
    /// developer's Mac on the LAN (if configured) — in that order, with
    /// duplicates removed. A fresh checkout with no local config still works
    /// against a locally running backend; a physical iPhone with the
    /// deployed URL configured never needs the Mac to be reachable at all.
    static var candidateBaseURLs: [URL] {
        var candidates: [URL] = []
        for url in [configuredAPIBaseURL, localhostBaseURL, configuredFallbackBaseURL] {
            guard let url, !candidates.contains(url) else { continue }
            candidates.append(url)
        }
        return candidates
    }

    private static var configuredAPIBaseURL: URL? {
        configuredURL(forInfoDictionaryKey: "API_BASE_URL")
    }

    private static var configuredFallbackBaseURL: URL? {
        configuredURL(forInfoDictionaryKey: "API_FALLBACK_BASE_URL")
    }

    private static func configuredURL(forInfoDictionaryKey key: String) -> URL? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("$"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
