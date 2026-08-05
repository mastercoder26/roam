import Foundation

@main
struct APIClientChecks {
    static func main() {
        backendJSONErrorsReachTheUser()
        rawResponseBodiesDoNotReachTheUser()
        aTimeoutOrCancellationEndsTheAttempt()
        theTimeBudgetIsSharedAcrossCandidates()

        print("API client checks passed")
    }

    private static func backendJSONErrorsReachTheUser() {
        expect(
            APIClient.userFacingErrorMessage(from: json(#"{"error":"Origin and destination must differ."}"#))
                == "Origin and destination must differ.",
            "the backend's own error text should still be shown"
        )
        expect(
            APIClient.userFacingErrorMessage(from: json(#"{"message":"That address could not be found."}"#))
                == "That address could not be found.",
            "a message field should be accepted like an error field"
        )
        expect(
            APIError.httpError(statusCode: 400, message: "Origin and destination must differ.").errorDescription
                == "Server error (400): Origin and destination must differ.",
            "a real backend message should keep its place in the banner"
        )
    }

    private static func rawResponseBodiesDoNotReachTheUser() {
        let proxyPage = Data(
            "<html><head><title>502 Bad Gateway</title></head><body><h1>502 Bad Gateway</h1></body></html>".utf8
        )
        expect(
            APIClient.userFacingErrorMessage(from: proxyPage) == nil,
            "a proxy's HTML error page must never be rendered as the banner text"
        )
        expect(
            APIError.httpError(statusCode: 502, message: nil).errorDescription == "Server error (502).",
            "an unreadable body should fall back to a generic, honest message"
        )

        expect(
            APIClient.userFacingErrorMessage(from: Data()) == nil,
            "an empty body carries no message"
        )
        expect(
            APIClient.userFacingErrorMessage(from: Data("Service Unavailable".utf8)) == nil,
            "a plain-text body is not a structured backend error"
        )
        expect(
            APIClient.userFacingErrorMessage(from: json(#"{"error":"  "}"#)) == nil,
            "a blank message should not produce an empty banner"
        )
        expect(
            APIClient.userFacingErrorMessage(from: json(#"{"error":"<h1>Gateway Timeout</h1>"}"#)) == nil,
            "markup smuggled through a JSON field is still markup"
        )

        let essay = String(repeating: "detail ", count: 200)
        expect(
            APIClient.userFacingErrorMessage(from: json(#"{"error":"\#(essay)"}"#)) == nil,
            "a page-sized message must not be pasted into a banner"
        )
    }

    private static func aTimeoutOrCancellationEndsTheAttempt() {
        expect(
            !APIClient.shouldTryNextCandidate(after: URLError(.timedOut)),
            "a timeout already spent the shared budget, so the next host must not get a fresh one"
        )
        expect(
            !APIClient.shouldTryNextCandidate(after: URLError(.cancelled)),
            "a cancelled analysis must not fire a second request at another host"
        )
        expect(
            !APIClient.shouldTryNextCandidate(after: CancellationError()),
            "a structured cancellation means stop"
        )
        expect(
            APIClient.shouldTryNextCandidate(after: URLError(.cannotConnectToHost)),
            "an unreachable host is still a reason to try the next one"
        )
        expect(
            APIClient.shouldTryNextCandidate(after: URLError(.notConnectedToInternet)),
            "a non-timeout network failure should not stop the fallback"
        )
    }

    private static func theTimeBudgetIsSharedAcrossCandidates() {
        expect(
            APIClient.maximumCandidateTimeout < APIClient.totalRequestBudget,
            "one candidate must not be able to consume the whole budget"
        )
        expect(
            APIClient.minimumCandidateTimeout > 0
                && APIClient.minimumCandidateTimeout < APIClient.maximumCandidateTimeout,
            "the leftover-budget floor must be a real, smaller bound"
        )
        expect(
            APIClient.totalRequestBudget <= 60,
            "the whole attempt should finish inside the old per-candidate timeout, not multiply it"
        )
    }

    private static func json(_ value: String) -> Data {
        Data(value.utf8)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("API client check failed: \(message)")
    }
}
