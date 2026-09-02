import Foundation

@main
struct LaunchReadinessChecks {
    static func main() {
        initialStateIsHidden()
        visualCompletionWaitsForBootstrap()
        bootstrapCompletionWaitsForVisual()
        bothOrdersRevealExactlyOnce()
        everyTerminalBootstrapStateReleasesAfterVisualCompletion()
        duplicateEventsAreIdempotent()
        staleGenerationCallbacksAreIgnored()
        replayStartsFreshVisualGenerationAndReusesBootstrapReadiness()
        reducedMotionAndSkipAreVisualCompletionSignals()
        presentationStateKeepsInitialLaunchIntroOnly()
        presentationStateSettlesToRootOnly()
        presentationStateKeepsMountedRootDuringReplay()
        presentationStateNeverMountsRootWithoutServices()

        print("Launch readiness checks passed")
    }

    private static func initialStateIsHidden() {
        let gate = LaunchReadinessGate()

        expect(!gate.isRevealed, "the launch gate must start hidden")
        expect(gate.bootstrapState == nil, "bootstrap must start without a terminal state")
        expect(gate.currentGeneration == nil, "a visual generation must not exist before the intro starts")
    }

    private static func visualCompletionWaitsForBootstrap() {
        let gate = LaunchReadinessGate()
        let generation = gate.beginVisualGeneration()

        expect(
            !gate.markVisualComplete(for: generation),
            "a complete intro must remain hidden while bootstrap is pending"
        )
        expect(!gate.isRevealed, "visual completion alone must not reveal the app")
    }

    private static func bootstrapCompletionWaitsForVisual() {
        let gate = LaunchReadinessGate()
        let generation = gate.beginVisualGeneration()

        expect(
            !gate.markBootstrapTerminal(.ready, for: generation),
            "bootstrap completion must remain hidden while the intro is pending"
        )
        expect(!gate.isRevealed, "bootstrap completion alone must not reveal the app")
    }

    private static func bothOrdersRevealExactlyOnce() {
        let visualFirst = LaunchReadinessGate()
        let visualFirstGeneration = visualFirst.beginVisualGeneration()
        expect(
            !visualFirst.markVisualComplete(for: visualFirstGeneration),
            "visual-first order must wait for bootstrap"
        )
        expect(
            visualFirst.markBootstrapTerminal(.ready, for: visualFirstGeneration),
            "bootstrap should release after visual completion"
        )
        expect(visualFirst.isRevealed, "visual-first order must reveal the app")

        let bootstrapFirst = LaunchReadinessGate()
        let bootstrapFirstGeneration = bootstrapFirst.beginVisualGeneration()
        expect(
            !bootstrapFirst.markBootstrapTerminal(.signedOut, for: bootstrapFirstGeneration),
            "bootstrap-first order must wait for the intro"
        )
        expect(
            bootstrapFirst.markVisualComplete(for: bootstrapFirstGeneration),
            "visual completion should release after bootstrap"
        )
        expect(bootstrapFirst.isRevealed, "bootstrap-first order must reveal the app")
    }

    private static func everyTerminalBootstrapStateReleasesAfterVisualCompletion() {
        let terminalStates: [LaunchReadinessGate.BootstrapTerminalState] = [
            .ready,
            .signedOut,
            .offline,
            .degraded,
            .recoverableFailure,
            .timedOut
        ]

        for state in terminalStates {
            let gate = LaunchReadinessGate()
            let generation = gate.beginVisualGeneration()
            expect(
                !gate.markBootstrapTerminal(state, for: generation),
                "\(state) must wait for visual completion"
            )
            expect(
                gate.markVisualComplete(for: generation),
                "\(state) must release once the visual completes"
            )
            expect(gate.isRevealed, "\(state) must leave the gate revealed")
            expect(gate.bootstrapState == state, "the terminal state must be retained")
        }
    }

    private static func duplicateEventsAreIdempotent() {
        let gate = LaunchReadinessGate()
        let generation = gate.beginVisualGeneration()

        expect(
            !gate.markBootstrapTerminal(.ready, for: generation),
            "the first terminal event must only record readiness"
        )
        expect(
            !gate.markBootstrapTerminal(.ready, for: generation),
            "duplicate bootstrap events must not trigger a second release"
        )
        expect(
            gate.markVisualComplete(for: generation),
            "the first visual completion must release the app"
        )
        expect(
            !gate.markVisualComplete(for: generation),
            "duplicate visual completions must not trigger a second release"
        )
        expect(
            !gate.markBootstrapTerminal(.signedOut, for: generation),
            "a later terminal state must not replace the first terminal event"
        )
        expect(gate.bootstrapState == .ready, "the first terminal state must remain authoritative")
    }

    private static func staleGenerationCallbacksAreIgnored() {
        let gate = LaunchReadinessGate()
        let oldGeneration = gate.beginVisualGeneration()
        let newGeneration = gate.beginVisualGeneration()

        expect(
            !gate.markVisualComplete(for: oldGeneration),
            "a stale visual callback must not release a newer generation"
        )
        expect(
            !gate.markBootstrapTerminal(.ready, for: oldGeneration),
            "a stale bootstrap callback must not update the newer generation"
        )
        expect(gate.bootstrapState == nil, "stale callbacks must leave bootstrap pending")
        expect(
            !gate.markVisualComplete(for: newGeneration),
            "the current generation must still wait for bootstrap"
        )
        expect(
            gate.markBootstrapTerminal(.ready, for: newGeneration),
            "the current generation should release normally"
        )
    }

    private static func replayStartsFreshVisualGenerationAndReusesBootstrapReadiness() {
        let gate = LaunchReadinessGate()
        let firstGeneration = gate.beginVisualGeneration()

        expect(
            !gate.markBootstrapTerminal(.offline, for: firstGeneration),
            "the initial offline terminal state should wait for the visual"
        )
        expect(
            gate.markVisualComplete(for: firstGeneration),
            "the first visual generation should release"
        )

        let replayGeneration = gate.beginVisualGeneration()
        expect(replayGeneration != firstGeneration, "replay must receive a fresh visual generation token")
        expect(!gate.isRevealed, "a replay must hide the app until its visual completes")
        expect(
            gate.markVisualComplete(for: replayGeneration),
            "replay should reuse the already-terminal bootstrap readiness"
        )
        expect(gate.isRevealed, "the completed replay must reveal the app")
    }

    private static func reducedMotionAndSkipAreVisualCompletionSignals() {
        let reducedMotion = LaunchReadinessGate()
        let reducedMotionGeneration = reducedMotion.beginVisualGeneration()
        expect(
            !reducedMotion.markBootstrapTerminal(.ready, for: reducedMotionGeneration),
            "reduced-motion bootstrap should still wait for the visual signal"
        )
        expect(
            reducedMotion.markVisualComplete(for: reducedMotionGeneration),
            "reduced motion should use the same visual completion signal"
        )

        let skipped = LaunchReadinessGate()
        let skippedGeneration = skipped.beginVisualGeneration()
        expect(
            !skipped.markBootstrapTerminal(.ready, for: skippedGeneration),
            "skipped intro bootstrap should still wait for the visual signal"
        )
        expect(
            skipped.markVisualComplete(for: skippedGeneration),
            "skipping the intro should use the same visual completion signal"
        )
    }

    private static func presentationStateKeepsInitialLaunchIntroOnly() {
        let state = LaunchPresentationState.resolve(
            hasMountedRoot: false,
            servicesAvailable: true,
            isIntroPlaying: true
        )

        expect(!state.shouldMountRoot, "initial launch must not mount the root behind the intro")
        expect(state.showsIntro, "initial launch must show the intro")
        expect(!state.rootAllowsInteraction, "an unmounted root cannot accept interaction")
    }

    private static func presentationStateSettlesToRootOnly() {
        let state = LaunchPresentationState.resolve(
            hasMountedRoot: true,
            servicesAvailable: true,
            isIntroPlaying: false
        )

        expect(state.shouldMountRoot, "a settled launch must keep the root mounted")
        expect(!state.showsIntro, "a settled launch must hide the intro")
        expect(!state.rootIsVisuallyHidden, "a settled root must be visible")
        expect(state.rootAllowsInteraction, "a settled root must accept interaction")
        expect(!state.rootIsAccessibilityHidden, "a settled root must be accessible")
    }

    private static func presentationStateKeepsMountedRootDuringReplay() {
        let state = LaunchPresentationState.resolve(
            hasMountedRoot: true,
            servicesAvailable: true,
            isIntroPlaying: true
        )

        expect(state.shouldMountRoot, "replay must preserve the already-mounted root")
        expect(state.showsIntro, "replay must show the intro overlay")
        expect(state.rootIsVisuallyHidden, "replay must visually hide the mounted root")
        expect(!state.rootAllowsInteraction, "replay must disable root interaction")
        expect(state.rootIsAccessibilityHidden, "replay must hide the root from accessibility")
    }

    private static func presentationStateNeverMountsRootWithoutServices() {
        let state = LaunchPresentationState.resolve(
            hasMountedRoot: true,
            servicesAvailable: false,
            isIntroPlaying: false
        )

        expect(!state.shouldMountRoot, "missing services must never mount the root")
        expect(!state.rootAllowsInteraction, "a root without services cannot accept interaction")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
