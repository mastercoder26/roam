import SwiftUI
import UIKit

/// Detail and replay presentation are isolated from the recording surface so
/// recording state, history navigation, and replay affordances can evolve
/// independently.
struct DriveDetailView: View {
    let drive: RecordedDrive
    @EnvironmentObject private var session: DriveSessionManager
    @State private var selectedMomentID: UUID?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(drive: RecordedDrive, initialSelectedMomentID: UUID? = nil) {
        self.drive = drive
        _selectedMomentID = State(initialValue: initialSelectedMomentID)
    }

    private var replayMoments: [DriveReplayMoment] {
        DriveReplayEngine.moments(for: drive)
    }

    private var selectedMoment: DriveReplayMoment? {
        guard let selectedMomentID else { return nil }
        return replayMoments.first(where: { $0.id == selectedMomentID })
    }

    private var hasUsableRoute: Bool {
        !DriveExperienceEngine.validTraceSegments(for: drive.route).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drive details").font(AppDesign.Typography.heroTitle)
                    Text(drive.startedAt.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if hasUsableRoute {
                    RecordedDriveMapView(
                        route: drive.route,
                        moments: replayMoments,
                        selectedEventID: selectedMomentID,
                        onSelectMoment: select
                    )
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
                } else {
                    ContentUnavailableView(
                        "Route unavailable",
                        systemImage: "location.slash",
                        description: Text("This drive did not receive a continuous accurate GPS trace to draw a route.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .premiumCard()
                }

                if let debrief = drive.plannedRouteContext?.debrief {
                    DriveDebriefSummary(debrief: debrief)
                }
                DriveRouteDifficultyCard(analysis: drive.routeAnalysis)
                DriveScoreCard(score: drive.score, title: "Drive score")
                replaySection
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.vertical, 12)
        }
        .background(AppDesign.canvas)
        .navigationTitle("Past drive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete drive")
            }
        }
        .confirmationDialog(
            "Delete this drive?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete drive", role: .destructive) {
                session.deleteDrive(id: drive.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the drive from this device. It cannot be undone.")
        }
    }

    private var replaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Moments that mattered",
                subtitle: "Tap a moment or map marker to review the measured context."
            )

            if replayMoments.isEmpty {
                Label("No coaching events were detected on this drive.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(replayMoments) { moment in
                    Button { select(moment) } label: {
                        ReplayMomentRow(moment: moment, isSelected: selectedMomentID == moment.id)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedMoment {
                Divider()
                ReplayMomentDetail(moment: selectedMoment)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .premiumCard()
        .animation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection, value: selectedMomentID)
    }

    private func select(_ moment: DriveReplayMoment) {
        guard selectedMomentID != moment.id else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection) {
            selectedMomentID = moment.id
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct DriveDebriefSummary: View {
    let debrief: PracticeDriveDebrief

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(AppDesign.positive)
                .frame(width: 30, height: 30)
                .background(AppDesign.positive.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(debrief.headline).font(.subheadline.weight(.semibold))
                Text(debrief.summary).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .premiumCard()
    }
}

struct DriveRouteAnalysisBadge: View {
    let analysis: DriveRouteAnalysis?

    var body: some View {
        HStack(spacing: 5) {
            switch analysis?.status {
            case .some(.available):
                Image(systemName: "map.fill")
                Text(routeDifficultyText)
            case .some(.pending):
                ProgressView().controlSize(.mini)
                Text("Analyzing route")
            case .some(.unavailable), nil:
                Image(systemName: "map.fill.badge.ellipsis")
                Text("Route difficulty unavailable")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(badgeColor)
        .accessibilityElement(children: .combine)
    }

    private var routeDifficultyText: String {
        guard let analysis,
              let score = analysis.difficultyScore,
              let label = analysis.label else {
            return "Route difficulty available"
        }
        return "Route \(String(format: "%.1f", score))/10 · \(label.rawValue)"
    }

    private var badgeColor: Color {
        guard let label = analysis?.label, analysis?.status == .available else { return .secondary }
        return label.color
    }
}

private struct DriveRouteDifficultyCard: View {
    let analysis: DriveRouteAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch analysis?.status {
            case .some(.available): availableContent
            case .some(.pending): pendingContent
            case .some(.unavailable), nil: unavailableContent
            }
        }
        .premiumCard()
    }

    private var availableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "map.fill", color: analysis?.label?.color ?? AppDesign.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route difficulty").font(.headline)
                    Text("Analyzed automatically from this drive’s start to destination.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f", analysis?.difficultyScore ?? 0))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/10 · \(analysis?.label?.rawValue ?? "Route")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(analysis?.label?.color ?? .secondary)
                }
            }
            if let highlights = analysis?.highlights, !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("What added demand").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "plus.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let detail = analysis?.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var pendingContent: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().tint(AppDesign.accent).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Analyzing route difficulty").font(.headline)
                Text("Roam saved this drive already and is analyzing the measured start and destination in the background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unavailableContent: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "map.fill.badge.ellipsis", color: .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Route difficulty unavailable").font(.headline)
                Text(analysis?.detail ?? "This saved drive did not have enough continuous GPS data to analyze a route from start to destination.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ReplayMomentRow: View {
    let moment: DriveReplayMoment
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: moment.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppDesign.accent : AppDesign.safety)
                .frame(width: 34, height: 34)
                .background((isSelected ? AppDesign.accent : AppDesign.safety).opacity(0.12), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(moment.kind.title).font(.subheadline.weight(.semibold))
                Text(relativeTime(moment.elapsedSinceDriveStart)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let speed = moment.nearestSpeedMetersPerSecond {
                    Text("\(Int((speed * 2.23694).rounded())) mph")
                        .font(.caption.weight(.medium).monospacedDigit())
                }
                Text(moment.locationAvailable ? "On route" : "Location unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? AppDesign.accent : Color(.tertiaryLabel))
        }
        .padding(10)
        .background(isSelected ? AppDesign.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? AppDesign.accent.opacity(0.22) : .clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func relativeTime(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded()))
        return String(format: "%d:%02d into drive", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct ReplayMomentDetail: View {
    let moment: DriveReplayMoment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(moment.kind.title).font(.subheadline.weight(.semibold))
            Text("Detected from \(moment.source.rawValue). This is a coaching signal, not a determination of unsafe driving.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let progress = moment.routeProgress {
                Text("Measured route progress: \(Int((progress * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This event is saved, but it could not be placed on a continuous GPS segment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DriveScoreCard: View {
    let score: DrivingScore
    let title: String

    init(score: DrivingScore, title: String = "Last drive") {
        self.score = score
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(score.grade)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(score.dataQuality.confidence == .low ? .orange : (score.score >= 78 ? .green : .orange))
                }
                Spacer()
                Text("\(score.score)").font(.system(size: 42, weight: .bold, design: .rounded))
                Text("/100").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(String(format: "%.1f", score.distanceMiles)) mi")
                Spacer()
                Text(score.formattedDuration)
                Spacer()
                Text("Top \(score.topSpeedMPH) mph")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            if !score.events.isEmpty {
                Divider()
                ForEach(DrivingEventKind.allCases.filter { score.count(for: $0) > 0 }) { event in
                    HStack {
                        Image(systemName: event.symbol).frame(width: 22).foregroundStyle(.orange)
                        Text(event.title)
                        Text(eventSource(for: event)).font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(score.count(for: event))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            Text(score.summary).font(.footnote).foregroundStyle(.secondary)
            Label(score.dataQuality.summary, systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let placement = score.dataQuality.placementQuality {
                Label(placementText(placement), systemImage: placementSymbol(placement))
                    .font(.footnote)
                    .foregroundStyle(placement == .needsAdjustment ? AppDesign.safety : .secondary)
            }
        }
        .premiumCard()
    }

    private func eventSource(for kind: DrivingEventKind) -> String {
        kind == .phoneMovement ? "motion" : "GPS / motion"
    }

    private func placementText(_ placement: PhonePlacementAssessment) -> String {
        switch placement {
        case .stable: "Sensor placement stayed stable during the measured first minute."
        case .needsAdjustment: "Sensor placement may be unstable. Secure the phone when it is safe."
        case .inconclusive: "Sensor placement did not have enough measured driving time to assess."
        case .unavailable: "Sensor placement could not be assessed because motion data was unavailable."
        }
    }

    private func placementSymbol(_ placement: PhonePlacementAssessment) -> String {
        switch placement {
        case .stable: "checkmark.circle"
        case .needsAdjustment: "iphone.gen3.radiowaves.left.and.right"
        case .inconclusive: "questionmark.circle"
        case .unavailable: "sensor.tag.radiowaves.forward"
        }
    }
}

struct FlipClock: View {
    enum Style: Equatable {
        case preview
        case active

        var digitWidth: CGFloat { self == .active ? 68 : 56 }
        var digitHeight: CGFloat { self == .active ? 96 : 76 }
        var digitFontSize: CGFloat { self == .active ? 56 : 48 }
        var colonFontSize: CGFloat { self == .active ? 38 : 30 }
        var spacing: CGFloat { self == .active ? 6 : 5 }
    }

    let elapsed: TimeInterval
    let style: Style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var digits: [String] {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return Array(String(format: "%02d%02d", minutes, seconds)).map(String.init)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(Int(elapsed) / 60):\(String(format: "%02d", Int(elapsed) % 60))")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AppDesign.Ink.primary)
            } else {
                HStack(spacing: style.spacing) {
                    ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                        if index == 2 {
                            Text(":")
                                .font(.system(size: style.colonFontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 1)
                        }
                        FlipClockDigit(digit: digit, style: style)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drive time \(Int(elapsed) / 60) minutes, \(Int(elapsed) % 60) seconds")
    }
}

private struct FlipClockDigit: View {
    let digit: String
    let style: FlipClock.Style

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppDesign.cornerRadiusTiny, style: .continuous)
    }

    var body: some View {
        ZStack {
            tile.fill(AppDesign.cardSurface)

            // Keying on the value makes each tick an insertion plus a removal,
            // which is what gives the flap something to animate. Without the
            // id, SwiftUI reuses one Text and the glyph simply swaps.
            Text(digit)
                .font(.system(size: style.digitFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppDesign.Ink.primary)
                .id(digit)
                .transition(flapTransition)

            // The hinge line sits above the glyph so a dropping flap passes
            // behind it, the way a real split-flap board reads.
            Rectangle().fill(AppDesign.cardStroke).frame(height: 1)
        }
        .frame(width: style.digitWidth, height: style.digitHeight)
        // Clipping to the tile is what turns a vertical move into a flap:
        // the outgoing glyph falls out of the card, the incoming one drops in.
        .clipShape(tile)
        .animation(reduceMotion ? nil : AppAnimation.flip, value: digit)
    }

    /// Reduced Motion keeps the digit legible and still — a timer must stay
    /// readable, so this degrades to a plain cross-fade rather than nothing.
    private var flapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }
}

struct DriveHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lifepreserver.fill").font(.system(size: 30)).foregroundStyle(.red)
            Text("Get help safely").font(.title2.weight(.bold))
            Text("If you feel unsafe, pull over in a safe place before using your phone. Roam cannot contact emergency services or monitor a crash.")
                .foregroundStyle(.secondary)
            Button("Call emergency services") {
                if let number = URL(string: "tel://911") { openURL(number) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Button("Close") { dismiss() }.buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
