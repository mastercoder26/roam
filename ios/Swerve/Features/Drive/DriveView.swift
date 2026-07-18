import SwiftUI

struct DriveView: View {
    private enum RecordingPresentation: Equatable {
        case idle
        case active
        case returning
    }

    @EnvironmentObject private var session: DriveSessionManager
    @State private var showingHelp = false
    @State private var recordingPresentation: RecordingPresentation = .idle
    @State private var actionShowsEnd = false
    @State private var transitionToken = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                        if showsSupportingContent {
                            header
                            if session.queuedPracticeRoute != nil {
                                practiceRouteReadyCard
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        recordingCard(availableHeight: geometry.size.height)
                            .id("drive-recording-surface")

                        if showsSupportingContent {
                            if let score = session.lastScore {
                                if let drive = session.lastCompletedDrive,
                                   drive.plannedRouteContext?.debrief != nil {
                                    PracticeDebriefCard(drive: drive)
                                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }
                                DriveScoreCard(score: score)
                            } else {
                                howItWorksCard
                            }

                            if !session.recordedDrives.isEmpty {
                                driveHistory
                            }
                        }
                    }
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDisabled(isTransitioningDriveSurface)
                .background(isFocusedCanvas ? Color(.systemBackground) : Color(.systemGroupedBackground))
            }
            .animation(driveModeAnimation, value: recordingPresentation)
            .navigationTitle(isFocusedCanvas ? "" : "Drive")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(isFocusedCanvas ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !isFocusedCanvas {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingHelp = true
                        } label: {
                            Label("Get help", systemImage: "lifepreserver.fill")
                        }
                        .accessibilityHint("Shows safety and emergency options")
                    }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            DriveHelpSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            guard session.isRecording else { return }
            actionShowsEnd = true
            recordingPresentation = .active
        }
    }

    private var activeSpeed: some View {
        VStack(spacing: 8) {
            Label("CURRENT SPEED", systemImage: "speedometer")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(session.currentSpeedMilesPerHour)")
                    .font(.system(size: 62, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("mph")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current speed \(session.currentSpeedMilesPerHour) miles per hour")
    }

    private var compactPlacementWarning: some View {
        Label("Secure the phone when it is safe", systemImage: "iphone.gen3.radiowaves.left.and.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppDesign.safety)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppDesign.safety.opacity(0.12), in: Capsule(style: .continuous))
            .accessibilityLabel("Sensor placement may be unstable. Secure the phone when it is safe.")
    }

    private var driveModeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.driveMode
    }

    private var actionSwapAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.12)
    }

    private var isExpandedDriveSurface: Bool {
        recordingPresentation == .active
    }

    private var isFocusedCanvas: Bool {
        recordingPresentation == .active || recordingPresentation == .returning
    }

    private var isTransitioningDriveSurface: Bool {
        recordingPresentation != .idle
    }

    private var showsSupportingContent: Bool {
        recordingPresentation == .idle
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Practice with purpose")
                .font(AppDesign.Typography.heroTitle)
                .tracking(-0.5)
            Text("Start and end each drive yourself. Your raw readings stay on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var practiceRouteReadyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 34, height: 34)
                    .background(AppDesign.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Practice route ready")
                        .font(.subheadline.weight(.semibold))
                    Text("Start manually when you’re ready. Swerve only counts this as route practice when saved GPS overlaps the route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    session.clearPlannedPracticeRoute()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityLabel("Cancel practice route")
                .accessibilityHint("Removes this planned route from the next drive")
            }

            if let plan = session.queuedPracticeRoute?.practicePlan, !plan.goals.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text("Practice goals")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(plan.goals) { goal in
                        Label(goal.title, systemImage: goal.requiresAdultSupervision ? "figure.and.child.holdinghands" : "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(goal.requiresAdultSupervision ? AppDesign.safety : AppDesign.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                .stroke(AppDesign.accent.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Practice route ready")
    }

    private func recordingCard(availableHeight: CGFloat) -> some View {
        let expandedHeight = max(availableHeight - 24, 560)

        return VStack(spacing: isExpandedDriveSurface ? 0 : 18) {
            Label(isExpandedDriveSurface ? "DRIVE STARTED" : "MANUAL DRIVE", systemImage: isExpandedDriveSurface ? "record.circle.fill" : "steeringwheel")
                .font(.caption.weight(.bold))
                .foregroundStyle(isExpandedDriveSurface ? .red : .secondary)
                .frame(maxWidth: .infinity, alignment: isExpandedDriveSurface ? .center : .leading)
                .padding(.top, isExpandedDriveSurface ? 28 : 0)

            FlipClock(elapsed: session.elapsed, style: isExpandedDriveSurface ? .active : .preview)
                .padding(.top, isExpandedDriveSurface ? 12 : 0)

            if isExpandedDriveSurface {
                Spacer(minLength: 34)
                activeSpeed

                if session.phonePlacementAssessment == .needsAdjustment {
                    compactPlacementWarning
                        .padding(.top, 20)
                        .transition(reduceMotion ? .opacity : .opacity)
                }

                Spacer(minLength: 34)
            }

            driveActionButton(showsEnd: actionShowsEnd)
                .padding(.horizontal, isExpandedDriveSurface ? AppDesign.contentPadding : 0)
                .padding(.bottom, isExpandedDriveSurface ? AppDesign.contentPadding : 0)

            if !isExpandedDriveSurface, recordingPresentation != .returning {
                Text(session.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .padding(isExpandedDriveSurface ? 0 : 20)
        .frame(maxWidth: .infinity)
        .frame(height: isExpandedDriveSurface ? expandedHeight : nil, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: isExpandedDriveSurface ? 0 : 24, style: .continuous)
                .fill(isFocusedCanvas ? Color(.systemBackground) : Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: isExpandedDriveSurface ? 0 : 24, style: .continuous)
                .stroke(isFocusedCanvas ? .clear : Color.primary.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(actionShowsEnd ? "Drive in progress" : "Manual drive")
    }

    private func driveActionButton(showsEnd: Bool) -> some View {
        Button {
            if showsEnd {
                endDrive()
            } else {
                startDrive()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: showsEnd ? "stop.fill" : "record.circle")
                Text(showsEnd ? "End drive" : "Start drive")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .fill(showsEnd ? Color.red : Color.accentColor)
            )
        }
        .buttonStyle(PressableScaleStyle())
        .contentTransition(.opacity)
        .accessibilityLabel(showsEnd ? "End drive" : "Start drive")
    }

    private func startDrive() {
        guard !session.isRecording else { return }
        transitionToken = UUID()
        let token = transitionToken
        session.startDrive()

        // First, make the action's meaning explicit. Only after that label
        // swap settles do we move the same button vertically to its driving
        // position.
        withAnimation(actionSwapAnimation) {
            actionShowsEnd = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.13)) {
            guard transitionToken == token, session.isRecording else { return }
            withAnimation(driveModeAnimation) {
                recordingPresentation = .active
            }
        }
    }

    private func endDrive() {
        guard session.isRecording else { return }
        transitionToken = UUID()
        let token = transitionToken
        session.endDrive()

        // Keep the End Drive label while its existing button returns along the
        // same vertical path. The start label returns only after it reaches
        // its original position.
        withAnimation(driveModeAnimation) {
            recordingPresentation = .returning
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.50)) {
            guard transitionToken == token else { return }
            withAnimation(actionSwapAnimation) {
                actionShowsEnd = false
                recordingPresentation = .idle
            }
        }
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What gets measured", subtitle: "A first-pass, on-device drive score. It is not a safety guarantee.")
            Label("GPS speed changes flag hard braking and rapid acceleration.", systemImage: "location.fill")
            Label("Possible phone handling needs sustained motion and device rotation while driving. One bump does not count.", systemImage: "waveform.path.ecg")
            Label("A physical iPhone is required for meaningful sensor data.", systemImage: "iphone")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .premiumCard()
    }

    private var driveHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Past drives", subtitle: "Routes and coaching events stay on this device.")
            ForEach(session.recordedDrives) { drive in
                NavigationLink {
                    DriveDetailView(drive: drive)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(drive.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                            Text("\(String(format: "%.1f", drive.score.distanceMiles)) mi · \(drive.score.events.count) coaching events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(drive.score.score)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(drive.score.score >= 78 ? .green : .orange)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if drive.id != session.recordedDrives.last?.id { Divider() }
            }
        }
        .premiumCard()
    }

}

private struct PracticeDebriefCard: View {
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
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: debriefSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(debriefColor)
                        .frame(width: 40, height: 40)
                        .background(debriefColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(debrief.headline).font(.headline)
                        Text(debrief.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !debrief.goalCompletions.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Practice goals")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        ForEach(debrief.goalCompletions) { completion in
                            let goal = planGoals.first(where: { $0.id == completion.goalID })
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: completion.wasMeasuredToday ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(completion.wasMeasuredToday ? AppDesign.positive : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(goal?.title ?? "Practice goal")
                                        .font(.footnote.weight(.semibold))
                                    Text(completion.status.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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

private struct DriveDetailView: View {
    let drive: RecordedDrive
    @State private var selectedMomentID: UUID?
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
                    Text(drive.startedAt.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                }

                if hasUsableRoute {
                    RecordedDriveMapView(
                        route: drive.route,
                        moments: replayMoments,
                        selectedEventID: selectedMomentID
                    ) { moment in
                        select(moment)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
                } else {
                    ContentUnavailableView("Route unavailable", systemImage: "location.slash", description: Text("This drive did not receive a continuous accurate GPS trace to draw a route."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .premiumCard()
                }

                if let debrief = drive.plannedRouteContext?.debrief {
                    DriveDebriefSummary(debrief: debrief)
                }
                DriveScoreCard(score: drive.score)
                replaySection
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Past drive")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var replaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Moments that mattered", subtitle: "Tap a moment or map marker to review the measured context.")

            if replayMoments.isEmpty {
                Label("No coaching events were detected on this drive.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(replayMoments) { moment in
                    Button {
                        select(moment)
                    } label: {
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

private struct ReplayMomentRow: View {
    let moment: DriveReplayMoment
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: moment.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppDesign.accent : AppDesign.safety)
                .frame(width: 34, height: 34)
                .background((isSelected ? AppDesign.accent : AppDesign.safety).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(moment.kind.title).font(.subheadline.weight(.semibold))
                Text(relativeTime(moment.elapsedSinceDriveStart))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct DriveScoreCard: View {
    let score: DrivingScore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last drive").font(.headline)
                    Text(score.grade).font(.footnote.weight(.semibold)).foregroundStyle(score.dataQuality.confidence == .low ? .orange : (score.score >= 78 ? .green : .orange))
                }
                Spacer()
                Text("\(score.score)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
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
                        Text(eventSource(for: event))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
        // Counts are grouped by event kind; source provenance is surfaced in the
        // score summary rather than pretending every occurrence had one source.
        kind == .phoneMovement ? "motion" : "GPS / motion"
    }

    private func placementText(_ placement: PhonePlacementAssessment) -> String {
        switch placement {
        case .stable:
            return "Sensor placement stayed stable during the measured first minute."
        case .needsAdjustment:
            return "Sensor placement may be unstable. Secure the phone when it is safe."
        case .inconclusive:
            return "Sensor placement did not have enough measured driving time to assess."
        case .unavailable:
            return "Sensor placement could not be assessed because motion data was unavailable."
        }
    }

    private func placementSymbol(_ placement: PhonePlacementAssessment) -> String {
        switch placement {
        case .stable: return "checkmark.circle"
        case .needsAdjustment: return "iphone.gen3.radiowaves.left.and.right"
        case .inconclusive: return "questionmark.circle"
        case .unavailable: return "sensor.tag.radiowaves.forward"
        }
    }
}

private struct FlipClock: View {
    enum Style: Equatable {
        case preview
        case active

        var digitWidth: CGFloat { self == .active ? 68 : 56 }
        var digitHeight: CGFloat { self == .active ? 92 : 76 }
        var digitFontSize: CGFloat { self == .active ? 60 : 48 }
        var colonFontSize: CGFloat { self == .active ? 38 : 30 }
        var spacing: CGFloat { self == .active ? 6 : 5 }
    }

    let elapsed: TimeInterval
    let style: Style

    private var digits: [String] {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return Array(String(format: "%02d%02d", minutes, seconds)).map(String.init)
    }

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drive time \(Int(elapsed) / 60) minutes, \(Int(elapsed) % 60) seconds")
    }
}

private struct FlipClockDigit: View {
    let digit: String
    let style: FlipClock.Style

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
            Text(digit)
                .font(.system(size: style.digitFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
        }
        .frame(width: style.digitWidth, height: style.digitHeight)
    }
}

private struct DriveHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lifepreserver.fill")
                .font(.system(size: 30))
                .foregroundStyle(.red)
            Text("Get help safely").font(.title2.weight(.bold))
            Text("If you feel unsafe, pull over in a safe place before using your phone. Swerve cannot contact emergency services or monitor a crash.")
                .foregroundStyle(.secondary)
            Button("Call emergency services") {
                if let number = URL(string: "tel://911") { openURL(number) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DriveView()
        .environmentObject(DriveSessionManager())
}
