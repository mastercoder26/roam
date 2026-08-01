import SwiftUI

/// Motion tokens aligned with Apple fluid-interface defaults:
/// critically damped springs for UI, snappy press feedback, no bounce on routine transitions.
enum AppAnimation {
    /// Default UI spring — no overshoot (damping 1.0, response 0.35)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 1.0)

    /// Route-choice selection and compact control changes. This stays crisp
    /// enough for repeated taps without making the interface feel nervous.
    static let selection = Animation.spring(response: 0.30, dampingFraction: 1.0)

    /// A slightly slower, still critically damped transition for a new card
    /// or a meaningful summary becoming available.
    static let content = Animation.spring(response: 0.40, dampingFraction: 1.0)

    /// The manual-drive state change carries a timer upward and the primary
    /// action downward. It remains critically damped so it is calm and can be
    /// immediately reversed when a drive ends.
    static let driveMode = Animation.spring(response: 0.42, dampingFraction: 1.0)

    /// Deliberate reveal (score arc, breakdown bars)
    static let reveal = Animation.spring(response: 0.5, dampingFraction: 1.0)

    /// Hero section entrance on results screen
    static let hero = Animation.spring(response: 0.45, dampingFraction: 1.0)

    /// Button press, suggestion dismiss — must feel instant
    static let press = Animation.spring(response: 0.2, dampingFraction: 1.0)

    /// High-frequency UI (search suggestions, error fade)
    static let quick = Animation.easeOut(duration: 0.18)

    /// Route / map camera — on-screen movement
    static let mapDuration: TimeInterval = 0.28
    static let map = Animation.easeInOut(duration: mapDuration)

    /// Stagger between hero elements only (score → map)
    static let heroStagger: Double = 0.08

    /// The floating tab bar's liquid-glass morph between its full bar and
    /// its collapsed, icon-only indicator. A touch of bounce reads as fluid
    /// rather than mechanical without overshooting into playful territory.
    static let liquidMorph = Animation.spring(response: 0.42, dampingFraction: 0.88)
}
