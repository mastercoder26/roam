import Foundation

@main
struct RoutePlanningLocationChecks {
    static func main() {
        expect(!RoutePlanningOriginState.awaitingOrigin.allowsDestination, "destination must be hidden before an origin is chosen")
        expect(RoutePlanningOriginState.locating.allowsDestination, "choosing current location should unlock destination while it resolves")
        expect(!RoutePlanningOriginState.manualEntry(message: nil).allowsDestination, "manual entry must be completed before destination is shown")
        expect(RoutePlanningOriginState.resolved("1 Infinite Loop, Cupertino, CA").allowsDestination, "resolved origin must unlock destination")
        print("Route planning location checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Route planning location check failed: \(message)") }
    }
}
