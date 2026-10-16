import Foundation

@main
struct ProfileHeaderPullChecks {
    static func main() {
        let resting = ProfileHeaderPull(offset: 0, reduceMotion: false)
        expect(resting.expansion == 0 && resting.blurRadius == 0 && resting.verticalOffset == 0,
               "the landscape must remain sharp and unchanged at rest")
        expect(ProfileHeaderPull(offset: -240, reduceMotion: false) == resting,
               "normal upward scrolling must not blur or stretch the image")

        let lightPull = ProfileHeaderPull(offset: 36, reduceMotion: false)
        let deepPull = ProfileHeaderPull(offset: 144, reduceMotion: false)
        expect(lightPull.expansion > 0 && lightPull.blurRadius > 0,
               "pulling beyond the top should enlarge and soften the landscape")
        expect(deepPull.expansion > lightPull.expansion && deepPull.blurRadius > lightPull.blurRadius,
               "the effect should increase continuously with the pull")
        expect(144 + deepPull.verticalOffset == 0,
               "the image must cover the top instead of exposing a blank overscroll gap")
        expect(ProfileHeaderPull(offset: 1_000, reduceMotion: false).blurRadius <= 12,
               "strong overscroll must not create an excessive blur")

        let reduced = ProfileHeaderPull(offset: 90, reduceMotion: true)
        expect(reduced.expansion == 0 && reduced.blurRadius == 0,
               "Reduce Motion must disable the additional zoom and blur")
        expect(90 + reduced.verticalOffset == 0,
               "the reduced-motion image must still cover the top")
        expect(ProfileHeaderPull(offset: 0, reduceMotion: false) == resting,
               "releasing the pull must restore the original sharp image")
        print("ProfileHeaderPull checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
