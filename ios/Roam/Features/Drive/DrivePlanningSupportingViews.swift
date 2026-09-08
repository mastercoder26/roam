import SwiftUI

/// Break timing and practice debrief UI are kept out of the recording surface
/// so drive capture state is not coupled to follow-up coaching presentation.
struct BreakRecommendationsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    let route: ScoredRoute
    let continuousMinutes: Double

    private var recommendation: BreakRecommendation {
        BreakRecommendation(route: route, continuousMinutes: continuousMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            HStack(alignment: .top, spacing: AppDesign.space12) {
                IconTile(symbol: recommendation.symbol, color: recommendation.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.semibold))
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !recommendation.stops.isEmpty {
                VStack(alignment: .leading, spacing: AppDesign.space8) {
                    ForEach(recommendation.stops) { stop in
                        HStack(spacing: 10) {
                            Text(stop.label)
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(recommendation.color)
                                .frame(width: 54, alignment: .leading)
                            Capsule(style: .continuous)
                                .fill(recommendation.color.opacity(0.18))
                                .frame(width: 3, height: 22)
                            Text(stop.reason)
                                .font(.caption)
                                .foregroundStyle(AppDesign.Ink.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .background(
                    AppDesign.cardSurface,
                    in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                )
            }
        }
    }
}

private struct BreakRecommendation {
    typealias Stop = StopBreakPlan.Stop

    let plan: StopBreakPlan
    let color: Color

    init(route: ScoredRoute, continuousMinutes: Double) {
        let plan = StopBreakPlan(route: route, continuousMinutes: continuousMinutes)
        self.plan = plan
        if plan.isRecommended {
            self.color = plan.highDemand ? AppDesign.safety : AppDesign.accent
        } else {
            self.color = AppDesign.positive
        }
    }

    var title: String { plan.title }
    var detail: String { plan.detail }
    var symbol: String { plan.symbol }
    var stops: [Stop] { plan.stops }
}

struct PracticeDebriefCard: View {
    @ObservedObject private var theme = ThemeManager.shared
    let drive: RecordedDrive

    private var debrief: PracticeDriveDebrief? {
        drive.plannedRouteContext?.debrief
    }

    private var planGoals: [PracticeGoal] {
        drive.plannedRouteContext?.practicePlan?.goals ?? []
    }

    var body: some View {
        if let debrief {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: AppDesign.space12) {
                    Image(systemName: debriefSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(debriefColor)
                        .frame(width: 40, height: 40)
                        .background(debriefColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(debrief.headline).font(.headline)
                        Text(debrief.summary)
                            .font(.footnote)
                            .foregroundStyle(AppDesign.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !debrief.goalCompletions.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: AppDesign.space8) {
                        Text("Practice goals")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppDesign.Ink.secondary)
                        ForEach(debrief.goalCompletions) { completion in
                            let goal = planGoals.first(where: { $0.id == completion.goalID })
                            HStack(alignment: .top, spacing: AppDesign.space8) {
                                Image(systemName: completion.wasMeasuredToday ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(completion.wasMeasuredToday ? AppDesign.positive : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(goal?.title ?? "Practice goal")
                                        .font(.footnote.weight(.semibold))
                                    Text(completion.status.title)
                                        .font(.caption)
                                        .foregroundStyle(AppDesign.Ink.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                NavigationLink {
                    DriveDetailView(drive: drive)
                } label: {
                    Label("Review moments", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppDesign.accent)
            }
            .premiumCard()
        }
    }

    private var debriefColor: Color {
        switch debrief?.outcome {
        case .some(.verifiedRoutePractice):
            return AppDesign.positive
        case .some(.partialRouteCoverage):
            return AppDesign.safety
        case .some(.insufficientGPSCoverage), .some(.savedNotYetQualifying):
            return AppDesign.accent
        case nil:
            return .secondary
        }
    }

    private var debriefSymbol: String {
        switch debrief?.outcome {
        case .some(.verifiedRoutePractice):
            return "checkmark.seal.fill"
        case .some(.partialRouteCoverage):
            return "point.3.connected.trianglepath.dotted"
        case .some(.insufficientGPSCoverage):
            return "location.slash"
        case .some(.savedNotYetQualifying):
            return "chart.bar.xaxis"
        case nil:
            return "checkmark.circle"
        }
    }
}
