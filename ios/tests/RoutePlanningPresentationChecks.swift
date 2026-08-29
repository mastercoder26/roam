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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("Route planning presentation check failed: \(message)")
        }
    }
}
