import Foundation

/// The terminal result of the app's bootstrap work. Every result is usable
/// enough to hand off from the launch visual; the UI decides how to present
/// the degraded result after the handoff.
final class LaunchReadinessGate {
    enum BootstrapTerminalState: Equatable {
        case ready
        case signedOut
        case offline
        case degraded
        case recoverableFailure
        case timedOut
    }

    /// A callback token for one visual run. A callback from an older run is
    /// ignored when a replay has already started.
    struct VisualGeneration: Equatable, Hashable {
        fileprivate let rawValue: UInt64
    }

    private(set) var currentGeneration: VisualGeneration?
    private(set) var bootstrapState: BootstrapTerminalState?

    private var completedVisualGeneration: VisualGeneration?
    private var revealedGeneration: VisualGeneration?
    private var nextGeneration: UInt64 = 0

    /// The app remains hidden until one visual generation and one terminal
    /// bootstrap result have both completed.
    var isRevealed: Bool {
        guard let currentGeneration else { return false }
        return revealedGeneration == currentGeneration
    }

    /// Starts (or re-starts) the visual handoff. A replay gets a new token,
    /// while an already-terminal bootstrap result is intentionally retained.
    @discardableResult
    func beginVisualGeneration() -> VisualGeneration {
        nextGeneration &+= 1
        let generation = VisualGeneration(rawValue: nextGeneration)
        currentGeneration = generation
        completedVisualGeneration = nil
        revealedGeneration = nil
        return generation
    }

    /// Records the visual completion signal. Skip and reduced-motion paths
    /// call this same method; the gate does not need to know how the visual
    /// completed.
    @discardableResult
    func markVisualComplete(for generation: VisualGeneration) -> Bool {
        guard currentGeneration == generation else { return false }
        guard completedVisualGeneration != generation else { return false }

        completedVisualGeneration = generation
        return releaseIfReady(for: generation)
    }

    /// Records the first terminal bootstrap result for the active visual run.
    /// Repeated results and callbacks belonging to an older run are ignored.
    @discardableResult
    func markBootstrapTerminal(
        _ state: BootstrapTerminalState,
        for generation: VisualGeneration
    ) -> Bool {
        guard currentGeneration == generation else { return false }
        guard bootstrapState == nil else { return false }

        bootstrapState = state
        return releaseIfReady(for: generation)
    }

    private func releaseIfReady(for generation: VisualGeneration) -> Bool {
        guard completedVisualGeneration == generation else { return false }
        guard bootstrapState != nil else { return false }
        guard revealedGeneration != generation else { return false }

        revealedGeneration = generation
        return true
    }
}

/// Pure presentation decisions for the root and launch overlay. The root may
/// remain mounted during a replay, but must be hidden from sight, interaction,
/// and accessibility until the intro has finished.
struct LaunchPresentationState: Equatable {
    let shouldMountRoot: Bool
    let showsIntro: Bool
    let rootIsVisuallyHidden: Bool
    let rootAllowsInteraction: Bool
    let rootIsAccessibilityHidden: Bool

    static func resolve(
        hasMountedRoot: Bool,
        servicesAvailable: Bool,
        isIntroPlaying: Bool
    ) -> LaunchPresentationState {
        let shouldMountRoot = hasMountedRoot && servicesAvailable
        let rootIsBlocked = shouldMountRoot && isIntroPlaying

        return LaunchPresentationState(
            shouldMountRoot: shouldMountRoot,
            showsIntro: isIntroPlaying,
            rootIsVisuallyHidden: rootIsBlocked,
            rootAllowsInteraction: shouldMountRoot && !isIntroPlaying,
            rootIsAccessibilityHidden: rootIsBlocked
        )
    }
}
