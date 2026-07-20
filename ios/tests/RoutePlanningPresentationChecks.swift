import Foundation

@main
struct RoutePlanningPresentationChecks {
    static func main() {
        destinationStaysHiddenUntilAUsableOriginExists()
        analyzeBecomesAvailableOnlyAfterBothEndpointsExist()

        print("Route planning presentation checks passed")
    }

    private static func destinationStaysHiddenUntilAUsableOriginExists() {
        expect(
            RoutePlanningStage(origin: "", destination: "") == .chooseOrigin,
            "a new route plan should begin by asking for the starting location"
        )
        expect(
            RoutePlanningStage(origin: "   ", destination: "Austin, TX") == .chooseOrigin,
            "whitespace must not reveal the destination field"
        )
        expect(
            RoutePlanningStage(origin: "Austin, TX", destination: "") == .chooseDestination,
            "the destination should appear once the start is resolved"
        )
    }

    private static func analyzeBecomesAvailableOnlyAfterBothEndpointsExist() {
        expect(
            RoutePlanningStage(origin: "Austin, TX", destination: "Dallas, TX") == .readyToAnalyze,
            "a complete route should enable the analysis action"
        )
        expect(
            RoutePlanningStage(origin: "Austin, TX", destination: "  ") == .chooseDestination,
            "an empty destination must not create an analyzable route"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Route planning presentation check failed: \(message)")
        }
    }
}
