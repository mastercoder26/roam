import Foundation

/// A small deterministic state machine for the Drive tab's recording
/// presentation. It deliberately carries no route, sensor, or drive data.
enum DrivePresentationPhase: Equatable {
    case idle
    case switchingToEnd
    case active
    case returning
    case switchingToStart
}

enum DrivePresentationAction: Equatable {
    case start
    case end
}

enum DrivePresentationEvent: Equatable {
    case startTapped
    case actionSwapCompleted
    case endTapped
    case returnMotionCompleted
    case startSwapCompleted
}

struct DrivePresentationState: Equatable {
    let phase: DrivePresentationPhase

    init(phase: DrivePresentationPhase = .idle) {
        self.phase = phase
    }

    var action: DrivePresentationAction {
        switch phase {
        case .idle, .switchingToStart:
            .start
        case .switchingToEnd, .active, .returning:
            .end
        }
    }

    /// Only the active phase shows the speed and places the action at the
    /// bottom. Returning keeps the same canvas but moves compact content up.
    var isExpanded: Bool {
        phase == .active
    }

    /// The canvas stays tall during the return, preventing a card-height
    /// collapse from competing with the button's upward movement.
    var preservesFocusedCanvas: Bool {
        switch phase {
        case .active, .returning, .switchingToStart:
            true
        case .idle, .switchingToEnd:
            false
        }
    }

    var showsSupportingContent: Bool {
        switch phase {
        case .idle, .switchingToEnd:
            true
        case .active, .returning, .switchingToStart:
            false
        }
    }

    var disablesScrolling: Bool {
        phase != .idle
    }
}

enum DrivePresentationEngine {
    /// The root view reserves the floating tab bar's measured height with a
    /// safe-area inset. This is only the card's local breathing room.
    static let activeButtonBottomInset: Double = 24

    static func reduce(
        _ state: DrivePresentationState,
        event: DrivePresentationEvent
    ) -> DrivePresentationState {
        let nextPhase: DrivePresentationPhase

        switch (state.phase, event) {
        case (.idle, .startTapped):
            nextPhase = .switchingToEnd
        case (.switchingToEnd, .actionSwapCompleted):
            nextPhase = .active
        case (.active, .endTapped):
            nextPhase = .returning
        case (.returning, .returnMotionCompleted):
            nextPhase = .switchingToStart
        case (.switchingToStart, .startSwapCompleted):
            nextPhase = .idle
        default:
            return state
        }

        return DrivePresentationState(phase: nextPhase)
    }
}
