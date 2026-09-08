import Foundation

@main
struct RoutePlanningPresentationChecks {
    static func main() {
        destinationIsVisibleBeforeAnOriginIsResolved()
        analyzeBecomesAvailableOnlyAfterBothEndpointsExist()
        mapPreviewProgressesFromStartPinToRouteLine()
        freshPlansKeepTheAppleMapsPreviewVisible()
        freshPlansWaitForAnExplicitOriginChoice()
        completedRoutesOfferTheCorrectAccountAction()
        breakRecommendationScoreGateGatesAtSevenScore()

        print("Route planning presentation checks passed")
    }

    private static func destinationIsVisibleBeforeAnOriginIsResolved() {
        expect(
            RoutePlanningStage(origin: "", destination: "") == .chooseOrigin,
            "a new route plan should begin by asking for the starting location"
        )
        expect(
            RoutePlanningFormPresentation(origin: "", destination: "", usesCurrentLocation: false).showsDestination,
            "both endpoints should be visible before a starting location is resolved"
        )
        expect(
            RoutePlanningFormPresentation(origin: "   ", destination: "Austin, TX", usesCurrentLocation: false).showsCurrentLocationAction,
            "an empty start should keep the explicit current-location action available"
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

    private static func mapPreviewProgressesFromStartPinToRouteLine() {
        expect(
            RoutePlanningMapPreviewStage(
                origin: "Austin, TX",
                destination: "",
                usesCurrentLocation: false
            ) == .startingPoint,
            "a typed starting location should plot before a destination is entered"
        )
        expect(
            RoutePlanningMapPreviewStage(
                origin: "Austin, TX",
                destination: "Dallas, TX",
                usesCurrentLocation: false
            ) == .route,
            "two valid endpoints should request a route line"
        )
        expect(
            RoutePlanningMapPreviewStage(
                origin: "",
                destination: "Dallas, TX",
                usesCurrentLocation: false
            ) == .locationPrompt,
            "a destination alone must not invent a starting location or a world map"
        )
    }

    private static func freshPlansKeepTheAppleMapsPreviewVisible() {
        expect(
            RoutePlanningMapPreviewStage(
                origin: "",
                destination: "",
                usesCurrentLocation: false
            ) == .locationPrompt,
            "a fresh plan should keep Apple Maps in its neutral preview state"
        )
    }

    private static func freshPlansWaitForAnExplicitOriginChoice() {
        expect(
            RoutePlanningFormState().originMode == .manual,
            "a fresh plan should wait for a typed start or an explicit current-location choice"
        )
    }

    private static func completedRoutesOfferTheCorrectAccountAction() {
        let stage = RoutePlanningStage(origin: "Austin, TX", destination: "Dallas, TX")

        expect(
            RoutePlanningPrimaryAction(
                stage: stage,
                isSignedIn: false,
                isAccountRestoring: false,
                isLoading: false
            ) == .signIn,
            "a signed-out completed route should offer sign-in instead of failing after a tap"
        )
        expect(
            RoutePlanningPrimaryAction(
                stage: stage,
                isSignedIn: false,
                isAccountRestoring: true,
                isLoading: false
            ) == .waitingForAccount,
            "a route should not open sign-in while Clerk is still restoring its session"
        )
        expect(
            RoutePlanningPrimaryAction(
                stage: stage,
                isSignedIn: true,
                isAccountRestoring: false,
                isLoading: false
            ) == .analyze,
            "a signed-in completed route should remain ready to analyze"
        )
    }

    private static func breakRecommendationScoreGateGatesAtSevenScore() {
        // Below 7.0 and without demands: low-demand 90-minute interval
        let easyRoute = ScoredRoute.stub(score: 6.9, durationSeconds: 7200)
        let easyPlan = StopBreakPlan(route: easyRoute, continuousMinutes: 0)
        expect(!easyPlan.highDemand, "score 6.9 must not be classified as high demand without explicit demands")
        expect(easyPlan.interval == 90, "low demand route must use 90 minute interval")
        expect(easyPlan.stops.count > 0, "a 120-minute drive should recommend stops")
        expect(easyPlan.stops.allSatisfy { $0.reason.contains("fatigue") }, "low demand stops should mention fatigue")

        // At or above 7.0: high-demand 60-minute interval even without demands
        let hardRoute = ScoredRoute.stub(score: 7.0, durationSeconds: 7200)
        let hardPlan = StopBreakPlan(route: hardRoute, continuousMinutes: 0)
        expect(hardPlan.highDemand, "score 7.0 must trigger high demand")
        expect(hardPlan.interval == 60, "high demand route must use 60 minute interval")
        expect(hardPlan.title == "Breaks recommended", "high demand plan must use 'Breaks recommended' title")
        expect(hardPlan.stops.allSatisfy { $0.reason.contains("Reset attention") }, "high demand stops must advise resetting attention")

        // Higher difficulty (8.5): high-demand 60-minute interval
        let veryHardRoute = ScoredRoute.stub(score: 8.5, durationSeconds: 7200)
        let veryHardPlan = StopBreakPlan(route: veryHardRoute, continuousMinutes: 0)
        expect(veryHardPlan.highDemand, "score 8.5 must trigger high demand")
        expect(veryHardPlan.interval == 60, "very hard route must use 60 minute interval")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Route planning presentation check failed: \(message)")
        }
    }
}
