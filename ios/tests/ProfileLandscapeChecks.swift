import Foundation

@main
struct ProfileLandscapeChecks {
    static func main() {
        for landscape in ProfileLandscape.allCases {
            for _ in 0..<50 {
                let next = ProfileLandscape.next(excluding: landscape.rawValue)
                expect(next != landscape, "opening Profile must avoid repeating the last landscape")
            }
        }

        let recovered = ProfileLandscape.next(excluding: "removed-or-corrupt-asset")
        expect(ProfileLandscape.allCases.contains(recovered), "an old saved selection must recover to a bundled landscape")
        expect(DriverProfile.empty.greeting == "Hello", "a missing name must have a natural greeting")
        expect(DriverProfile(displayName: "   \n ", stage: .permit).greeting == "Hello", "whitespace must not create an empty name")
        expect(DriverProfile(displayName: "  Akhil  Konduru ", stage: .permit).greeting == "Hello, Akhil", "use the first name without changing the stored full name")
        expect(DriverProfile(displayName: "李 明", stage: .licensed).greeting == "Hello, 李", "greetings must support Unicode names")
        print("ProfileLandscape checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
