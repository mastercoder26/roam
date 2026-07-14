import Foundation

enum DifficultyAPIError: LocalizedError {
    case invalidURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The backend URL is invalid."
        case .server(let message): message
        }
    }
}

struct DifficultyAPI {
    func score(
        origin: String,
        destination: String,
        includeAlternates: Bool,
        continuousDriveMinutes: Int?,
        baseURL: String
    ) async throws -> DifficultyResponse {
        let cleanedBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(cleanedBaseURL)/api/route/difficulty") else {
            throw DifficultyAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 35
        request.httpBody = try JSONEncoder().encode(
            DifficultyRequest(
                origin: origin,
                destination: destination,
                departureTime: ISO8601DateFormatter().string(from: Date()),
                includeAlternates: includeAlternates,
                continuousDriveMinutes: continuousDriveMinutes
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DifficultyAPIError.server("No response from the difficulty service.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).error)
                ?? "The difficulty service returned HTTP \(http.statusCode)."
            throw DifficultyAPIError.server(message)
        }
        return try JSONDecoder().decode(DifficultyResponse.self, from: data)
    }

    private struct APIError: Decodable { let error: String }
}
