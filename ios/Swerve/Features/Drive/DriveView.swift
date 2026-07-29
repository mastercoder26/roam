import SwiftUI

struct DriveView: View {
    @EnvironmentObject private var session: DriveSessionManager
    @State private var showingHelp = false
    @State private var presentationState = DrivePresentationState()
    @State private var transitionToken = UUID()
    @State private var routeOrigin = ""
    @State private var routeDestination = ""
    @State private var routeDepartureTime = Date().addingTimeInterval(15 * 60)
    @State private var isPlanningBreaks = false
    @State private var plannedBreakRoute: ScoredRoute?
    @State private var breakPlanningError: String?
    @State private var usesCurrentRouteOrigin = true
    /// Visible viewport height below the Swerve wordmark / above the tab bar.
    @State private var viewportHeight: CGFloat = 640
    @State private var pendingDeletionID: UUID?
    @State private var breakPlanningControlsWidth: CGFloat = 0
    @StateObject private var routeLocationCoordinator = RoutePlanningLocationCoordinator()
    private let apiClient = APIClient()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    if showsSupportingContent {
                        driveToolbar
                    }

                    recordingCard(availableHeight: viewportHeight)
                        .id("drive-recording-surface")

                    if showsSupportingContent {
                        breakPlanningCard
                        if session.queuedPracticeRoute != nil {
                            practiceRouteReadyCard
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        }

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
                // Drop outer padding while focused so the canvas height matches
                // the viewport exactly. That keeps the End Drive path vertical
                // and prevents the control from sliding under the tab bar.
                .padding(.horizontal, isFocusedCanvas ? 0 : AppDesign.contentPadding)
                .padding(.top, isFocusedCanvas ? 0 : 8)
                .padding(.bottom, isFocusedCanvas ? 0 : 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(isTransitioningDriveSurface)
            // Avoid wrapping ScrollView in GeometryReader — that ignores the
            // top wordmark safe-area inset and clips the start-drive card.
            .background(isFocusedCanvas ? Color(.systemBackground) : AppDesign.canvas)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { viewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in
                            viewportHeight = height
                        }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Delete this drive?",
                isPresented: Binding(
                    get: { pendingDeletionID != nil },
                    set: { if !$0 { pendingDeletionID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete drive", role: .destructive) {
                    guard let pendingDeletionID else { return }
                    withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.content) {
                        session.deleteDrive(id: pendingDeletionID)
                    }
                    self.pendingDeletionID = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletionID = nil
                }
            } message: {
                Text("This removes the drive from this device. It cannot be undone.")
            }
        }
        .sheet(isPresented: $showingHelp) {
            DriveHelpSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if usesCurrentRouteOrigin, routeOrigin.isEmpty {
                routeLocationCoordinator.useCurrentLocation()
            }
            guard session.isRecording else { return }
            presentationState = DrivePresentationState(phase: .active)
        }
        .onChange(of: routeLocationCoordinator.state) { _, state in
            if case .resolved(let address) = state { routeOrigin = address }
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

    /// Settling windows used when chaining start/stop phases. Slightly longer
    /// than the spring response so layout finishes before the next step.
    private var actionSwapSettlingNanos: UInt64 {
        reduceMotion ? 130_000_000 : 150_000_000
    }

    private var driveModeSettlingNanos: UInt64 {
        reduceMotion ? 200_000_000 : 480_000_000
    }

    private var isExpandedDriveSurface: Bool {
        presentationState.isExpanded
    }

    private var isFocusedCanvas: Bool {
        presentationState.preservesFocusedCanvas
    }

    private var isTransitioningDriveSurface: Bool {
        presentationState.disablesScrolling
    }

    private var showsSupportingContent: Bool {
        presentationState.showsSupportingContent
    }

    private var driveToolbar: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "lifepreserver.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary.opacity(0.88))
                    .frame(width: 36, height: 36)
                    .background(AppDesign.Ink.primary.opacity(0.10), in: Circle())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("Get help")
            .accessibilityHint("Shows safety and emergency options")
        }
    }


    private var breakPlanningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AddressSearchField(
                title: "Break-plan destination",
                placeholder: "Where are you driving?",
                systemImage: "magnifyingglass",
                iconColor: .secondary,
                text: $routeDestination
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                startingPointControl

                if usesCurrentRouteOrigin {
                    Button {
                        routeLocationCoordinator.useCurrentLocation()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(AppDesign.accent)
                            Text(routeOrigin.isEmpty ? "Use current location" : routeOrigin)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            if case .locating = routeLocationCoordinator.state {
                                ProgressView().tint(AppDesign.accent)
                            }
                        }
                        .padding(12)
                        .background(AppDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                    }
                    .buttonStyle(PressableScaleStyle())
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    AddressSearchField(
                        title: "Break-plan starting address",
                        placeholder: "Enter starting address",
                        systemImage: "circle.fill",
                        iconColor: AppDesign.accent,
                        text: $routeOrigin
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.content, value: usesCurrentRouteOrigin)

            DatePicker("Departure", selection: $routeDepartureTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)

            if let breakPlanningError {
                Label(breakPlanningError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.safety)
                    .transition(.opacity)
            }

            if let plannedBreakRoute {
                BreakRecommendationsView(route: plannedBreakRoute, continuousMinutes: session.elapsed / 60)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            Button {
                Task { await planBreaks() }
            } label: {
                HStack(spacing: 10) {
                    if isPlanningBreaks { ProgressView().tint(.white) }
                    Image(systemName: "cup.and.saucer.fill")
                    Text(isPlanningBreaks ? "Checking route…" : "Show break timing")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous).fill(canPlanBreaks ? AppDesign.accent : Color(.systemGray3)))
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(!canPlanBreaks)
        }
        .premiumCard()
        .animation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.content, value: plannedBreakRoute)
        .animation(AppAnimation.quick, value: breakPlanningError)
    }

    private var usesLargeText: Bool {
        dynamicTypeSize.isAccessibilitySize || dynamicTypeSize >= .xxLarge
    }

    private var shouldStackBreakPlanningControls: Bool {
        LayoutResponsiveness.stacksInlineControls(
            availableWidth: breakPlanningControlsWidth,
            usesLargeText: usesLargeText
        )
    }

    private var startingPointControl: some View {
        Group {
            if shouldStackBreakPlanningControls {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Starting point")
                        .font(.subheadline.weight(.semibold))
                    startingPointPicker
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack {
                    Text("Starting point")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 12)
                    startingPointPicker
                        .frame(maxWidth: 190)
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updateBreakPlanningControlsWidth(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, width in
                        updateBreakPlanningControlsWidth(width)
                    }
            }
        }
    }

    private var startingPointPicker: some View {
        Picker("Starting point", selection: $usesCurrentRouteOrigin) {
            Text("Current").tag(true)
            Text("Address").tag(false)
        }
        .pickerStyle(.segmented)
    }

    private func updateBreakPlanningControlsWidth(_ width: CGFloat) {
        guard width > 0, abs(breakPlanningControlsWidth - width) > 0.5 else { return }
        breakPlanningControlsWidth = width
    }

    private var canPlanBreaks: Bool {
        !isPlanningBreaks &&
            !routeOrigin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !routeDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func planBreaks() async {
        guard canPlanBreaks else { return }
        withAnimation(AppAnimation.quick) {
            isPlanningBreaks = true
            breakPlanningError = nil
        }
        do {
            let response = try await apiClient.analyzeRoute(
                origin: routeOrigin,
                destination: routeDestination,
                departureTime: routeDepartureTime,
                includeAlternates: false,
                continuousDriveMinutes: session.elapsed / 60
            )
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : AppAnimation.content) {
                plannedBreakRoute = response.primaryRoute
                isPlanningBreaks = false
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(AppAnimation.quick) {
                breakPlanningError = error.localizedDescription
                isPlanningBreaks = false
            }
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
                    Text("Practice route")
                        .font(.subheadline.weight(.semibold))
                    Text("Swerve only counts this as route practice when saved GPS overlaps the route.")
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
        // Never force a taller canvas than the visible area. A floor here used
        // to push End Drive under the floating tab bar once the brand mark and
        // tab inset reduced available height.
        let expandedHeight = max(availableHeight, 0)
        let keepsFocusedCanvas = presentationState.preservesFocusedCanvas
        let actionShowsEnd = presentationState.action == .end
        // Clearance below the persistent Swerve wordmark so the flip clock
        // never sits under the header chrome.
        let focusedTopClearance: CGFloat = 28

        return VStack(spacing: isExpandedDriveSurface ? 0 : 18) {
            if isExpandedDriveSurface {
                Spacer(minLength: 8)

                VStack(spacing: 24) {
                    FlipClock(elapsed: session.elapsed, style: .active)

                    activeSpeed

                    if session.phonePlacementAssessment == .needsAdjustment {
                        compactPlacementWarning
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 16)

                driveActionButton(showsEnd: actionShowsEnd)
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.bottom, CGFloat(DrivePresentationEngine.activeButtonBottomInset))
            } else {
                FlipClock(elapsed: session.elapsed, style: .preview)

                driveActionButton(showsEnd: actionShowsEnd)
                    .padding(.horizontal, keepsFocusedCanvas ? AppDesign.contentPadding : 0)

                if !keepsFocusedCanvas {
                    Text(session.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, keepsFocusedCanvas ? focusedTopClearance : 0)
        .padding(keepsFocusedCanvas ? 0 : 20)
        .frame(maxWidth: .infinity)
        // Do not collapse the canvas while the End Drive control is travelling
        // back to the compact position. That keeps the reverse path vertical.
        .frame(height: keepsFocusedCanvas ? expandedHeight : nil, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: keepsFocusedCanvas ? 0 : 24, style: .continuous)
                .fill(isFocusedCanvas ? Color(.systemBackground) : Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: keepsFocusedCanvas ? 0 : 24, style: .continuous)
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
        guard presentationState.phase == .idle, !session.isRecording else { return }
        transitionToken = UUID()
        let token = transitionToken

        // Label swap first, then the vertical expand. Timed settles are more
        // reliable here than spring completion callbacks, which can skip steps
        // when layout and toolbar chrome change in the same turn.
        withAnimation(actionSwapAnimation) {
            presentationState = DrivePresentationEngine.reduce(
                presentationState,
                event: .startTapped
            )
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: actionSwapSettlingNanos)
            guard transitionToken == token,
                  presentationState.phase == .switchingToEnd,
                  !session.isRecording else {
                return
            }

            session.startDrive()
            withAnimation(driveModeAnimation) {
                presentationState = DrivePresentationEngine.reduce(
                    presentationState,
                    event: .actionSwapCompleted
                )
            }
        }
    }

    private func endDrive() {
        guard presentationState.phase == .active, session.isRecording else { return }
        transitionToken = UUID()
        let token = transitionToken
        session.endDrive()

        // Keep the End Drive label while the control travels back up the same
        // vertical path, then swap to Start only after that motion settles.
        withAnimation(driveModeAnimation) {
            presentationState = DrivePresentationEngine.reduce(
                presentationState,
                event: .endTapped
            )
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: driveModeSettlingNanos)
            guard transitionToken == token,
                  presentationState.phase == .returning else {
                return
            }

            withAnimation(actionSwapAnimation) {
                presentationState = DrivePresentationEngine.reduce(
                    presentationState,
                    event: .returnMotionCompleted
                )
            }

            try? await Task.sleep(nanoseconds: actionSwapSettlingNanos)
            guard transitionToken == token,
                  presentationState.phase == .switchingToStart else {
                return
            }

            withAnimation(driveModeAnimation) {
                presentationState = DrivePresentationEngine.reduce(
                    presentationState,
                    event: .startSwapCompleted
                )
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
            SectionHeader(title: "Past drives", subtitle: "Routes and coaching events stay on this device. Touch and hold to delete.")
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
                            DriveRouteAnalysisBadge(analysis: drive.routeAnalysis)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(drive.score.score)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(drive.score.score >= 78 ? .green : .orange)
                            Text("drive score")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        pendingDeletionID = drive.id
                    } label: {
                        Label("Delete drive", systemImage: "trash")
                    }
                }
                .accessibilityHint("Touch and hold to delete this drive")
                if drive.id != session.recordedDrives.last?.id { Divider() }
            }
        }
        .premiumCard()
    }

}

private struct BreakRecommendationsView: View {
    let route: ScoredRoute
    let continuousMinutes: Double

    private var recommendation: BreakRecommendation {
        BreakRecommendation(route: route, continuousMinutes: continuousMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: recommendation.symbol, color: recommendation.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.semibold))
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !recommendation.stops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
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
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            }
        }
    }
}

private struct BreakRecommendation {
    struct Stop: Identifiable {
        let id = UUID()
        let minute: Int
        let reason: String

        var label: String {
            let hours = minute / 60
            let minutes = minute % 60
            if hours > 0, minutes > 0 { return "~\(hours)h \(minutes)m" }
            if hours > 0 { return "~\(hours)h" }
            return "~\(minutes)m"
        }
    }

    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let stops: [Stop]

    init(route: ScoredRoute, continuousMinutes: Double) {
        let routeMinutes = Double(route.durationSeconds) / 60
        let highDemand = (route.routeDemands ?? []).contains { demand in
            demand.available && (demand.level == .high || demand.intensity >= 0.66)
        } || route.score >= 70
        let longDrive = routeMinutes >= 90
        let interval = highDemand ? 60 : 90
        let firstBreak = max(30, interval - Int(continuousMinutes.rounded(.down)))
        let breakMinutes = stride(from: firstBreak, through: Int(routeMinutes.rounded(.down)), by: interval)
            .filter { $0 < Int(routeMinutes.rounded(.down)) - 10 }
            .prefix(3)
            .map { Stop(minute: $0, reason: highDemand ? "Reset attention before the demanding stretch continues." : "Step out before fatigue builds.") }

        if longDrive || highDemand || continuousMinutes >= 45 {
            title = highDemand ? "Breaks recommended" : "Long-drive breaks"
            detail = "This route is about \(Self.durationLabel(routeMinutes)). Swerve factors in your current continuous driving time and suggests rest timing before you start."
            symbol = "cup.and.saucer.fill"
            color = highDemand ? AppDesign.safety : AppDesign.accent
            stops = Array(breakMinutes)
        } else {
            title = "No planned stop needed"
            detail = "This route is about \(Self.durationLabel(routeMinutes)), so Swerve does not recommend an automatic rest stop right now."
            symbol = "checkmark.circle.fill"
            color = AppDesign.positive
            stops = []
        }
    }

    private static func durationLabel(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        let hours = rounded / 60
        let mins = rounded % 60
        if hours > 0, mins > 0 { return "\(hours) hr \(mins) min" }
        if hours > 0 { return "\(hours) hr" }
        return "\(mins) min"
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
                DriveRouteDifficultyCard(analysis: drive.routeAnalysis)
                DriveScoreCard(score: drive.score, title: "Drive score")
                replaySection
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Past drive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
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

private struct DriveRouteAnalysisBadge: View {
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
            case .some(.available):
                availableContent
            case .some(.pending):
                pendingContent
            case .some(.unavailable), nil:
                unavailableContent
            }
        }
        .premiumCard()
    }

    private var availableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "map.fill", color: analysis?.label?.color ?? AppDesign.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route difficulty")
                        .font(.headline)
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
                    Text("What added demand")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "plus.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let detail = analysis?.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pendingContent: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().tint(AppDesign.accent)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Analyzing route difficulty")
                    .font(.headline)
                Text("Swerve saved this drive already and is analyzing the measured start and destination in the background.")
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
                Text("Route difficulty unavailable")
                    .font(.headline)
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
        var digitHeight: CGFloat { self == .active ? 96 : 76 }
        var digitFontSize: CGFloat { self == .active ? 56 : 48 }
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
