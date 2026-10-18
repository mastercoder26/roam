import SwiftUI

struct HowRoamWorksSheet: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    private let factors = RouteFactorExplanation.all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(HowRoamWorksLayoutSpec.sectionSpacing)) {
                    introduction
                    processSection
                    VStack(alignment: .leading, spacing: AppDesign.space12) {
                        scoreSection
                        factorsSection
                        evidenceSection
                        recordedDriveSection
                        privacySection
                    }
                    limitsSection
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.top, CGFloat(HowRoamWorksLayoutSpec.topPadding))
                .padding(.bottom, CGFloat(HowRoamWorksLayoutSpec.bottomPadding))
                .frame(maxWidth: CGFloat(HowRoamWorksLayoutSpec.maximumContentWidth))
                .frame(maxWidth: .infinity)
            }
            .background(AppCanvasBackground())
            .accessibilityIdentifier("howRoamWorks.content")
            .navigationTitle("How Roam works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 52, height: 52)
                .background(AppDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            Text("Know what to expect")
                .font(.largeTitle.weight(.bold))
                .tracking(-0.4)
                .foregroundStyle(AppDesign.Ink.primary)

            Text("See the demanding parts of a route before you leave, then review your practice after each drive.")
                .font(.body)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, AppDesign.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var processSection: some View {
        HowItWorksSection(title: "Before you go", expandable: false) {
            VStack(spacing: 0) {
                ProcessStepRow(
                    number: 1,
                    title: "Choose a route",
                    detail: "Enter your start, destination, and departure time."
                )
                ExplanationDivider()
                ProcessStepRow(
                    number: 2,
                    title: "Check the conditions",
                    detail: "See traffic, weather, daylight, and difficult turns."
                )
                ExplanationDivider()
                ProcessStepRow(
                    number: 3,
                    title: "Compare options",
                    detail: "Review the difficulty and alternatives before choosing."
                )
            }
            .padding(.horizontal, AppDesign.cardPadding)
            .padding(.vertical, AppDesign.space4)
            .menuSurface()
        }
    }

    private var factorsSection: some View {
        HowItWorksSection(title: "What the route score considers") {
            VStack(spacing: 0) {
                ForEach(Array(factors.enumerated()), id: \.element.id) { index, factor in
                    RouteFactorRow(factor: factor)
                    if index < factors.count - 1 {
                        ExplanationDivider()
                    }
                }
            }
        }
    }

    private var evidenceSection: some View {
        HowItWorksSection(title: "How confidence is shown") {
            VStack(alignment: .leading, spacing: 0) {
                EvidenceLevelRow(
                    title: "Well supported",
                    detail: "Key route data is available.",
                    symbol: "checkmark.seal.fill",
                    color: AppDesign.positive
                )
                ExplanationDivider()
                EvidenceLevelRow(
                    title: "Partial evidence",
                    detail: "Some data is missing. Check the gaps listed with the score.",
                    symbol: "circle.lefthalf.filled",
                    color: AppDesign.safety
                )
                ExplanationDivider()
                EvidenceLevelRow(
                    title: "Limited evidence",
                    detail: "Little route data is available. Treat the score as an early estimate.",
                    symbol: "exclamationmark.circle.fill",
                    color: AppDesign.Ink.secondary
                )
            }
        }
    }

    private var scoreSection: some View {
        HowItWorksSection(title: "What the score means") {
            VStack(alignment: .leading, spacing: AppDesign.space12) {
                ScoreMeaningRow(range: "0 to 1.9", label: "Very easy", color: AppDesign.positive)
                ScoreMeaningRow(range: "2 to 3.9", label: "Easy", color: AppDesign.positive)
                ScoreMeaningRow(range: "4 to 5.9", label: "Moderate", color: AppDesign.safety)
                ScoreMeaningRow(range: "6 to 7.9", label: "Hard", color: AppDesign.safety)
                ScoreMeaningRow(range: "8 to 10", label: "Very hard", color: AppDesign.danger)

                Divider()

                Text("Higher means a harder route. This score does not rate the driver.")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recordedDriveSection: some View {
        HowItWorksSection(title: "What a recorded drive measures") {
            VStack(spacing: 0) {
                RecordedSignalRow(
                    title: "Route trace",
                    detail: "GPS continuity, distance, speed, duration, and overlap with a planned practice route.",
                    symbol: "location.fill"
                )
                ExplanationDivider()
                RecordedSignalRow(
                    title: "Speed changes",
                    detail: "Measured changes in speed can identify rapid acceleration and hard braking events.",
                    symbol: "speedometer"
                )
                ExplanationDivider()
                RecordedSignalRow(
                    title: "Turning motion",
                    detail: "Motion and course changes can identify sharper cornering when sensor quality is sufficient.",
                    symbol: "arrow.turn.up.right"
                )
                ExplanationDivider()
                RecordedSignalRow(
                    title: "Experience coverage",
                    detail: "Qualifying miles can contribute to after-dark, faster-road, continuous-driving, and weekly progress totals.",
                    symbol: "chart.line.uptrend.xyaxis"
                )
            }
        }
    }

    private var privacySection: some View {
        HowItWorksSection(title: "Your recorded drives") {
            ExplanationRowLayout {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: CGFloat(HowRoamWorksLayoutSpec.iconSize), height: CGFloat(HowRoamWorksLayoutSpec.iconSize))
                    .background(AppDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: AppDesign.space8) {
                    Text("Based on your practice")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text("Roam compares each route with your recorded practice, including familiar roads, longer drives, night driving, and faster roads.")
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your name and license stage do not affect scores.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var limitsSection: some View {
        HowItWorksSection(title: "Before you drive", expandable: false) {
            VStack(alignment: .leading, spacing: AppDesign.space12) {
                LimitRow(text: "A score is not a safety guarantee. Road data may be incomplete and conditions can change.")
                LimitRow(text: "Check conditions before leaving. Follow license restrictions and supervision rules.")
                LimitRow(text: "Choose an easier route or a qualified supervising driver when needed.")
            }
            .premiumCard()
        }
    }
}

private struct HowItWorksSection<Content: View>: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let title: String
    var expandable = true
    @ViewBuilder var content: Content

    @ViewBuilder
    var body: some View {
        if expandable {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : AppAnimation.selection) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppDesign.space16) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppDesign.Ink.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppDesign.Ink.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 16, height: 24)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, AppDesign.cardPadding)
                    .padding(.vertical, AppDesign.Menu.rowPadding)
                    .frame(minHeight: AppDesign.Menu.minimumRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Hides this explanation" : "Shows this explanation")

                if isExpanded {
                    Divider().padding(.horizontal, AppDesign.cardPadding)
                    content
                        .padding(.horizontal, AppDesign.cardPadding)
                        .padding(.top, AppDesign.space12)
                        .padding(.bottom, AppDesign.space16)
                        .transition(.opacity)
                }
            }
            .menuSurface()
        } else {
            VStack(alignment: .leading, spacing: CGFloat(HowRoamWorksLayoutSpec.titleContentSpacing)) {
                sectionTitle
                content
            }
        }
    }

    private var sectionTitle: some View {
        Text(title)
            .font(AppDesign.Typography.sectionTitle)
            .foregroundStyle(AppDesign.Ink.primary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Keep the copy in a full-width column when accessibility text is large.
private struct ExplanationRowLayout<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppDesign.space12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppDesign.space12))
        layout { content }
    }
}

private struct ExplanationDivider: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Divider()
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : CGFloat(HowRoamWorksLayoutSpec.rowTextInset))
    }
}

private struct RecordedSignalRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        ExplanationRowLayout {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppDesign.Ink.secondary)
                .frame(width: 36, height: 36)
                .background(AppDesign.trackSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: AppDesign.space4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(HowRoamWorksLayoutSpec.rowVerticalPadding))
        .accessibilityElement(children: .combine)
    }
}

private struct ProcessStepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        ExplanationRowLayout {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(AppDesign.accentForeground)
                .frame(width: CGFloat(HowRoamWorksLayoutSpec.iconSize), height: CGFloat(HowRoamWorksLayoutSpec.iconSize))
                .background(AppDesign.accent, in: Circle())

            VStack(alignment: .leading, spacing: AppDesign.space4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(HowRoamWorksLayoutSpec.rowVerticalPadding))
        .accessibilityElement(children: .combine)
    }
}

private struct RouteFactorExplanation: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    static let all: [RouteFactorExplanation] = [
        .init(id: "traffic", title: "Traffic", detail: "Expected congestion and delay around the selected departure time.", symbol: "car.2.fill"),
        .init(id: "fast-roads", title: "Fast roads", detail: "Distance and time spent on roads with higher posted speeds.", symbol: "speedometer"),
        .init(id: "merges", title: "Merges", detail: "Highway entries, exits, and lane changes identified along the route.", symbol: "arrow.triangle.merge"),
        .init(id: "intersections", title: "Complex intersections", detail: "Dense maneuvers, difficult junctions, and closely spaced decisions.", symbol: "arrow.triangle.branch"),
        .init(id: "weather", title: "Weather and visibility", detail: "Forecast precipitation, wind, visibility, and other conditions along the trip.", symbol: "cloud.sun.rain.fill"),
        .init(id: "dark", title: "After-dark driving", detail: "The share of the trip expected to occur outside daylight hours.", symbol: "moon.stars.fill"),
        .init(id: "duration", title: "Sustained drive", detail: "Total drive time and how long attention must be maintained continuously.", symbol: "clock.fill"),
        .init(id: "road", title: "Road conditions", detail: "Road class, mapped construction, turn controls, and available roadway metadata.", symbol: "road.lanes")
    ]
}

private struct RouteFactorRow: View {
    let factor: RouteFactorExplanation

    var body: some View {
        ExplanationRowLayout {
            Image(systemName: factor.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(width: 36, height: 36)
                .background(AppDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: AppDesign.space4) {
                Text(factor.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text(factor.detail)
                    .font(.caption)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(HowRoamWorksLayoutSpec.rowVerticalPadding))
        .accessibilityElement(children: .combine)
    }
}

private struct EvidenceLevelRow: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        ExplanationRowLayout {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: CGFloat(HowRoamWorksLayoutSpec.iconSize), height: CGFloat(HowRoamWorksLayoutSpec.iconSize))
            VStack(alignment: .leading, spacing: AppDesign.space4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(HowRoamWorksLayoutSpec.rowVerticalPadding))
        .accessibilityElement(children: .combine)
    }
}

private struct ScoreMeaningRow: View {
    let range: String
    let label: String
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppDesign.space12) {
                rangeText.fixedSize()
                Spacer(minLength: AppDesign.space12)
                difficultyBadge.fixedSize()
            }
            VStack(alignment: .leading, spacing: AppDesign.space8) {
                rangeText
                difficultyBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var rangeText: some View {
        Text(range)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(AppDesign.Ink.primary)
    }

    private var difficultyBadge: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct LimitRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.space8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppDesign.Ink.secondary)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HowRoamWorksSheet()
}
