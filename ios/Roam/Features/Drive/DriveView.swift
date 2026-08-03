import SwiftUI

struct DriveView: View {
    @ObservedObject private var theme = ThemeManager.shared
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
    /// Visible viewport height below the Roam wordmark / above the tab bar.
    @State private var viewportHeight: CGFloat = 640
    @State private var pendingDeletionID: UUID?
    @State private var breakPlanningControlsWidth: CGFloat = 0
    @StateObject private var routeLocationCoordinator = RoutePlanningLocationCoordinator()
    /// Ties the clock and the primary action across the compact and expanded
    /// branches below. Those are two separate `if`/`else` hierarchies, so
    /// without this SwiftUI destroys and rebuilds both controls instead of
    /// carrying them between positions.
    @Namespace private var driveTransition
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
            .background(AppDesign.canvas)
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
                .foregroundStyle(AppDesign.Ink.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(session.currentSpeedMilesPerHour)")
                    .font(.system(size: 62, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("mph")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.secondary)
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
        reduceMotion ? AppAnimation.tabSwitchReduced : AppAnimation.actionSwap
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
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
            .background(AppDesign.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                    .stroke(AppDesign.cardStrokeStrong, lineWidth: 1)
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
                                .foregroundStyle(AppDesign.Ink.primary)
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
                    if isPlanningBreaks {
                        ProgressView()
                            .tint(canPlanBreaks ? AppDesign.accentForeground : AppDesign.Ink.tertiary)
                    }
                    Image(systemName: "cup.and.saucer.fill")
                    Text(isPlanningBreaks ? "Checking route…" : "Show break timing")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(canPlanBreaks ? AppDesign.accentForeground : AppDesign.Ink.tertiary)
                .background(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous).fill(canPlanBreaks ? AppDesign.accent : AppDesign.disabledSurface))
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
                    Text("Roam only counts this as route practice when saved GPS overlaps the route.")
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    session.clearPlannedPracticeRoute()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .frame(width: 32, height: 32)
                        .background(AppDesign.trackSurface, in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
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
                        .foregroundStyle(AppDesign.Ink.secondary)
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
        // Clearance below the persistent Roam wordmark so the flip clock
        // never sits under the header chrome.
        let focusedTopClearance: CGFloat = 28

        return VStack(spacing: isExpandedDriveSurface ? 0 : 18) {
            if isExpandedDriveSurface {
                Spacer(minLength: 8)

                VStack(spacing: 24) {
                    FlipClock(elapsed: session.elapsed, style: .active)
                        .matchedGeometryEffect(id: DriveTransitionID.clock, in: driveTransition)

                    activeSpeed

                    if session.phonePlacementAssessment == .needsAdjustment {
                        compactPlacementWarning
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 16)

                driveActionButton(showsEnd: actionShowsEnd)
                    .matchedGeometryEffect(id: DriveTransitionID.action, in: driveTransition)
                    .padding(.horizontal, AppDesign.contentPadding)
                    .padding(.bottom, CGFloat(DrivePresentationEngine.activeButtonBottomInset))
            } else {
                FlipClock(elapsed: session.elapsed, style: .preview)
                    .matchedGeometryEffect(id: DriveTransitionID.clock, in: driveTransition)

                driveActionButton(showsEnd: actionShowsEnd)
                    .matchedGeometryEffect(id: DriveTransitionID.action, in: driveTransition)
                    .padding(.horizontal, keepsFocusedCanvas ? AppDesign.contentPadding : 0)

                if !keepsFocusedCanvas {
                    Text(session.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
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
                .fill(isFocusedCanvas ? AppDesign.canvas : AppDesign.cardSurfaceElevated)
        )
        .overlay {
            RoundedRectangle(cornerRadius: keepsFocusedCanvas ? 0 : 24, style: .continuous)
                .stroke(isFocusedCanvas ? .clear : AppDesign.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(actionShowsEnd ? "Drive in progress" : "Manual drive")
    }

    /// Shared identities for the controls that travel between the compact and
    /// expanded drive layouts.
    private enum DriveTransitionID {
        static let clock = "drive.clock"
        static let action = "drive.action"
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
                    // The glyph morphs between record and stop instead of
                    // popping, which reads as one control changing role.
                    .contentTransition(.symbolEffect(.replace))
                Text(showsEnd ? "End drive" : "Start drive")
                    .contentTransition(.interpolate)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(showsEnd ? AppDesign.dangerForeground : AppDesign.accentForeground)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .fill(showsEnd ? AppDesign.danger : AppDesign.accent)
            )
            // The fill is animated here rather than inherited so the accent →
            // red crossfade tracks the same spring as the travel downward.
            .animation(driveModeAnimation, value: showsEnd)
        }
        .buttonStyle(PressableScaleStyle())
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
        .foregroundStyle(AppDesign.Ink.secondary)
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
                            .foregroundStyle(AppDesign.accent)
                            .frame(width: 30, height: 30)
                            .background(AppDesign.accent.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(drive.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                            Text("\(String(format: "%.1f", drive.score.distanceMiles)) mi · \(drive.score.events.count) coaching events")
                                .font(.caption)
                                .foregroundStyle(AppDesign.Ink.secondary)
                            DriveRouteAnalysisBadge(analysis: drive.routeAnalysis)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(drive.score.score)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(drive.score.score >= 78 ? AppDesign.positive : AppDesign.safety)
                            Text("drive score")
                                .font(.caption2)
                                .foregroundStyle(AppDesign.Ink.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(AppDesign.Ink.tertiary)
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

#Preview {
    DriveView()
        .environmentObject(DriveSessionManager())
}
