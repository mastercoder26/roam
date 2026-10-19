import SwiftUI

struct DriveView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var session: DriveSessionManager
    @EnvironmentObject private var authSession: AuthSessionStore
    @State private var showingHelp = false
    @State private var showingPracticeGoals = false
    @State private var showsSavedSummary = false
    @State private var showingBreakPlanner = false
    @State private var presentationState = DrivePresentationState()
    @State private var transitionToken = UUID()
    @State private var routeOrigin = ""
    @State private var routeDestination = ""
    @State private var routeDepartureTime = Date().addingTimeInterval(15 * 60)
    @State private var isPlanningBreaks = false
    @State private var plannedBreakRoute: ScoredRoute?
    @State private var breakPlanningError: String?
    @State private var usesCurrentRouteOrigin = true
    @State private var pendingDeletionID: UUID?
    @State private var breakPlanningControlsWidth: CGFloat = 0
    @StateObject private var routeLocationCoordinator = RoutePlanningLocationCoordinator()
    private let apiClient = APIClient()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Group {
                if session.isRecording {
                    LiveDriveRecordingView(onEnd: endDrive)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                            if showsSupportingContent {
                                driveToolbar
                            }

                            if showsSavedSummary, let drive = session.lastCompletedDrive {
                                savedDriveSummary(drive)
                                Button("New drive") { showsSavedSummary = false }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.large)
                            } else {
                                recordingCard
                                    .id("drive-recording-surface")
                            }

                            if showsSupportingContent {
                                SectionHeader(title: "Before you go")
                                breakPlanningEntry
                                if session.queuedPracticeRoute != nil {
                                    practiceRouteReadyCard
                                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }

                                if let drive = session.lastCompletedDrive,
                                   drive.plannedRouteContext?.debrief != nil {
                                    PracticeDebriefCard(drive: drive)
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
                        .padding(.bottom, isFocusedCanvas ? 0 : AppDesign.space24)
                        .frame(maxWidth: isFocusedCanvas ? .infinity : AppDesign.maximumContentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDisabled(isTransitioningDriveSurface)
                }
            }
            .contentMargins(.bottom, isFocusedCanvas ? 0 : AppDesign.tabBarClearance, for: .scrollContent)
            .background(AppCanvasBackground())
            .toolbar(session.isRecording ? .hidden : .visible, for: .tabBar)
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
                Text("This drive will be permanently deleted.")
            }
        }
        .sheet(isPresented: $showingPracticeGoals) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Practice goals").font(.largeTitle.bold())
                        if session.queuedPracticeRoute != nil { practiceRouteReadyCard }
                        else {
                            Text("Choose a route in Routes, then select Practice this route to use its goals on your next drive.")
                                .foregroundStyle(AppDesign.Ink.secondary)
                        }
                    }.padding(20)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingPracticeGoals = false }
                } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingHelp) {
            DriveHelpSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingBreakPlanner) {
            NavigationStack {
                ScrollView {
                    breakPlanningCard
                        .padding(.horizontal, AppDesign.contentPadding)
                        .padding(.vertical, AppDesign.space16)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(AppCanvasBackground())
                .navigationTitle("Recovery stop")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingBreakPlanner = false }
                            .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            syncPresentationState(isRecording: session.isRecording, animated: false)
        }
        .onChange(of: session.lastCompletedDrive?.id) { _, id in
            if id != nil { showsSavedSummary = true }
        }
        .onChange(of: session.isRecording) { _, isRecording in
            syncPresentationState(isRecording: isRecording, animated: true)
        }
        .onChange(of: routeLocationCoordinator.state) { _, state in
            if case .resolved(let address) = state { routeOrigin = address }
        }
        .onChange(of: session.liveEvents.count) { previous, current in
            // A coaching event is the one thing on this screen the driver must
            // notice without looking. Warning-weight, and only on an increase
            // so resetting the list between drives stays silent.
            guard current > previous else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func syncPresentationState(isRecording: Bool, animated: Bool) {
        let targetPhase: DrivePresentationPhase = isRecording ? .active : .idle
        guard presentationState.phase != targetPhase else { return }

        // Don't interrupt in-flight user tap sequences
        if isRecording {
            guard presentationState.phase != .switchingToEnd else { return }
        } else {
            guard presentationState.phase != .returning && presentationState.phase != .switchingToStart else { return }
        }

        if animated {
            withAnimation(driveModeAnimation) {
                presentationState = DrivePresentationState(phase: targetPhase)
            }
        } else {
            presentationState = DrivePresentationState(phase: targetPhase)
        }
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
        reduceMotion ? 100_000_000 : 120_000_000
    }

    private var driveModeSettlingNanos: UInt64 {
        reduceMotion ? 180_000_000 : 320_000_000
    }

    private var isFocusedCanvas: Bool {
        session.isRecording
    }

    private var isTransitioningDriveSurface: Bool {
        presentationState.disablesScrolling
    }

    private var showsSupportingContent: Bool {
        !session.isRecording
    }

    private var driveToolbar: some View {
        CompactScreenHeader(title: showsSavedSummary ? "Drive saved" : "Drive")
        .overlay(alignment: .trailing) {
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                    .frame(width: 44, height: 44)
                    .background(AppDesign.trackSurface, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("Get help")
            .accessibilityHint("Shows safety and emergency options")
        }
        .accessibilityElement(children: .contain)
    }


    private var breakPlanningEntry: some View {
        VStack(spacing: 0) {
            Button { showingPracticeGoals = true } label: {
                AppMenuRow(title: "Practice goals", subtitle: "Choose what to work on", symbol: "checklist")
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 60)
        Button {
            showingBreakPlanner = true
        } label: {
            AppMenuRow(
                title: "Plan a recovery stop",
                subtitle: plannedBreakRoute == nil ? "Optional for longer drives" : "Recommendation ready",
                symbol: "cup.and.saucer"
            )
        }
        .buttonStyle(.plain)
        }
        .menuSurface()
        .accessibilityLabel("Before you go")
        .accessibilityValue(plannedBreakRoute == nil ? "Optional" : "Recommendation ready")
        .accessibilityHint("Opens break timing options")
    }

    private var breakPlanningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: AppDesign.space12) {
                IconTile(symbol: "cup.and.saucer.fill", color: AppDesign.safety, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Plan a recovery stop")
                        .font(AppDesign.Typography.sectionTitle)
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text("Choose a break for a longer drive.")
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AddressSearchField(
                title: "Break-plan destination",
                placeholder: "Where are you driving?",
                systemImage: "magnifyingglass",
                iconColor: .secondary,
                maximumSuggestions: 1,
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
                        maximumSuggestions: 1,
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
                VStack(alignment: .leading, spacing: AppDesign.space8) {
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
            let response = try await authSession.performAuthenticated { token in
                try await apiClient.analyzeRoute(
                    origin: routeOrigin,
                    destination: routeDestination,
                    departureTime: routeDepartureTime,
                    accessToken: token,
                    includeAlternates: false,
                    continuousDriveMinutes: session.elapsed / 60
                )
            }
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
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            HStack(alignment: .top, spacing: AppDesign.space12) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppDesign.accent)
                    .frame(width: 34, height: 34)
                    .background(AppDesign.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: AppDesign.space4) {
                    Text("Practice route")
                        .font(.subheadline.weight(.semibold))
                    Text("Counts as practice only when saved GPS overlaps the route.")
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

    private var recordingCard: some View {
        VStack(spacing: 12) {
            Text("Ready to record")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppDesign.Ink.secondary)
            FlipClock(elapsed: 0, style: .preview)
            Text("Secure your phone before starting.")
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
            driveActionButton(showsEnd: false)
                .accessibilityIdentifier("drive.start")
        }
        .frame(maxWidth: .infinity)
        .heroCard()
    }

    private func savedDriveSummary(_ drive: RecordedDrive) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(drive.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline).foregroundStyle(AppDesign.Ink.secondary)
            if !drive.route.isEmpty {
                RecordedDriveMapView(route: drive.route, moments: [], onSelectMoment: { _ in })
                    .frame(height: 184)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Text(drive.score.dataQuality.confidence == .low ? "—" : String(drive.score.score))
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(AppDesign.positive)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drive.score.dataQuality.confidence == .low ? "No score yet" : "Drive score").font(.headline)
                        DriveRouteAnalysisBadge(analysis: drive.routeAnalysis)
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) {
                        savedMetric(String(format: "%.1f", drive.score.distanceMiles), "Miles")
                        savedMetric(String(format: "%02d:%02d", Int(drive.score.duration) / 60, Int(drive.score.duration) % 60), "Drive time")
                        savedMetric("\(drive.score.events.count)", "Events")
                    }
                } else {
                    HStack {
                        savedMetric(String(format: "%.1f", drive.score.distanceMiles), "Miles")
                        savedMetric(String(format: "%02d:%02d", Int(drive.score.duration) / 60, Int(drive.score.duration) % 60), "Drive time")
                        savedMetric("\(drive.score.events.count)", "Events")
                    }
                }
            }
            .premiumCard()
            NavigationLink { DriveDetailView(drive: drive) } label: {
                Text("Review this drive").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(AppDesign.Ink.primary)
            .accessibilityIdentifier("drive.reviewSaved")
        }
        .accessibilityIdentifier("drive.savedSummary")
    }

    private func savedMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(AppDesign.Ink.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
            .foregroundStyle(showsEnd ? AppDesign.dangerForeground : AppDesign.primarySurfaceForeground)
            .background(
                Capsule()
                    .fill(showsEnd ? AppDesign.danger : AppDesign.Ink.primary)
            )
            .shadow(color: AppDesign.cardShadow.opacity(0.55), radius: 16, y: 7)
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

        // Keep the End Drive label while the control travels back up the same
        // vertical path, then swap to Start only after that motion settles.
        // Transition presentationState to .returning before ending the session so
        // the session.isRecording observer sees the in-flight return motion and
        // preserves the reverse choreography.
        withAnimation(driveModeAnimation) {
            presentationState = DrivePresentationEngine.reduce(
                presentationState,
                event: .endTapped
            )
        }

        session.endDrive()

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

    private var driveHistory: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(title: "Past drives")
            ForEach(session.recordedDrives) { drive in
                NavigationLink {
                    DriveDetailView(drive: drive)
                } label: {
                    HStack(spacing: AppDesign.space12) {
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
                            Text(drive.score.dataQuality.confidence == .low ? "—" : String(drive.score.score))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(drive.score.dataQuality.confidence == .low ? AppDesign.Ink.secondary : drive.score.score >= 78 ? AppDesign.positive : AppDesign.safety)
                            Text(drive.score.dataQuality.confidence == .low ? "Insufficient data" : "drive score")
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

/// A focused recorder. Data continues to come from the shared manual session;
/// the controls sheet never owns or resets recording state.
private struct LiveDriveRecordingView: View {
    @EnvironmentObject private var session: DriveSessionManager
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsControls = false
    @State private var controlsLocked = false
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(0.55, geometry.size.height / 658))
            VStack(spacing: 0) {
                FlipClock(elapsed: session.elapsed, style: .active)
                    .padding(.top, 16)
                Spacer(minLength: 12)
                metric(value: speed, label: "Speed (mph)", size: dynamicTypeSize.isAccessibilitySize ? 84 : 164 * scale)
                    .accessibilityIdentifier("drive.liveSpeed")
                Spacer(minLength: 12)
                metric(value: String(format: "%.1f", session.currentDistanceMiles), label: "Distance (mi)", size: dynamicTypeSize.isAccessibilitySize ? 64 : 100 * scale)
                    .accessibilityIdentifier("drive.liveDistance")
                Spacer(minLength: 12)
                Label(status, systemImage: session.isPaused ? "pause.circle.fill" : session.hasReliableGPS ? "record.circle.fill" : "location.slash")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(session.isPaused || session.hasReliableGPS ? AppDesign.Ink.secondary : AppDesign.safety)
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("drive.recordingStatus")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
        }
        .background(AppCanvasBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .sheet(isPresented: $showsControls) {
            DriveRecordingControls(onEnd: {
                showsControls = false
                onEnd()
            }, onLock: {
                controlsLocked = true
                showsControls = false
            })
            .presentationDetents([.height(414), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(36)
            .presentationBackground(Color(.secondarySystemBackground))
            .preferredColorScheme(.dark)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drive.liveRecording")
    }

    private var speed: String {
        guard !session.isPaused, session.hasReliableGPS else { return "—" }
        return String(session.currentSpeedMilesPerHour)
    }

    private var status: String {
        if session.isPaused { return "Drive paused" }
        if !session.hasReliableGPS { return "GPS signal is weak" }
        if session.phonePlacementAssessment == .needsAdjustment { return "Secure the phone when it is safe" }
        return "Recording"
    }

    private func metric(value: String, label: String, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .black))
                .fontWidth(.condensed)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(session.hasReliableGPS ? AppDesign.Ink.primary : AppDesign.Ink.tertiary)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppDesign.Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var dock: some View {
        VStack(spacing: 14) {
            if controlsLocked {
                HoldToUnlockControl(onUnlock: unlock)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                Button { showsControls = true } label: {
                    Capsule().fill(AppDesign.Ink.tertiary).frame(width: 38, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Drive controls")
                .accessibilityIdentifier("drive.showControls")
                Button {
                    togglePause()
                    showsControls = true
                } label: {
                    Label(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .foregroundStyle(AppDesign.recordingActionForeground)
                        .background(AppDesign.recordingAction, in: Capsule())
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityIdentifier("drive.pauseResume")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 5)
        .padding(.bottom, 16)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(AppDesign.cardSurface)
                .ignoresSafeArea(edges: .bottom)
        }
        .gesture(DragGesture(minimumDistance: 16).onEnded { value in
            if !controlsLocked, value.translation.height < -20 { showsControls = true }
        })
    }

    private func togglePause() {
        UISelectionFeedbackGenerator().selectionChanged()
        if session.isPaused { session.resumeDrive() } else { session.pauseDrive() }
    }

    private func unlock() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            controlsLocked = false
        }
    }
}

private struct HoldToUnlockControl: View {
    private static let holdDuration = 1.1
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHolding = false
    @State private var isUnlocked = false
    @State private var progress = 0.0
    @State private var feedbackTask: Task<Void, Never>?
    let onUnlock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(AppDesign.Ink.primary.opacity(0.12), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress)
                    .stroke(AppDesign.Ink.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(isUnlocked ? -12 : 0))
                    .scaleEffect(isUnlocked ? 1.12 : 1)
            }
            .frame(width: 38, height: 38)
            Text(isUnlocked ? "Unlocked" : isHolding ? "Keep holding…" : "Hold to unlock controls")
                .font(.headline)
                .contentTransition(.opacity)
        }
        .foregroundStyle(AppDesign.Ink.primary)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background {
            GeometryReader { geometry in
                Capsule().fill(AppDesign.Ink.primary.opacity(0.09))
                    .frame(width: geometry.size.width * progress)
            }
            .clipShape(Capsule())
        }
        .overlay {
            Capsule().strokeBorder(AppDesign.Ink.primary.opacity(isHolding ? 0.3 : 0.12), lineWidth: 0.75)
        }
        .shadow(color: AppDesign.Ink.primary.opacity(isHolding ? 0.1 : 0), radius: 14)
        .scaleEffect(isHolding ? 0.97 : 1)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 28, pressing: { pressed in
            if pressed { beginHold() } else if !isUnlocked { cancelHold() }
        }, perform: finishHold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to unlock controls")
        .accessibilityValue(isUnlocked ? "Unlocked" : "Locked")
        .accessibilityHint("Hold for one second to unlock. Release to cancel.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { finishHold() }
        .accessibilityIdentifier("drive.unlockControls")
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelHold() }
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    private func beginHold() {
        guard !isHolding, !isUnlocked else { return }
        feedbackTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { isHolding = true }
        withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
        feedbackTask = Task { @MainActor in
            do {
                let tick = UIImpactFeedbackGenerator(style: .light)
                tick.prepare()
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                tick.impactOccurred(intensity: 0.55)
                let next = UIImpactFeedbackGenerator(style: .medium)
                next.prepare()
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                next.impactOccurred(intensity: 0.8)
            } catch { return }
        }
    }

    private func cancelHold() {
        feedbackTask?.cancel()
        guard !isUnlocked else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isHolding = false
            progress = 0
        }
    }

    private func finishHold() {
        guard !isUnlocked, scenePhase == .active else { return }
        feedbackTask?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isUnlocked = true
            isHolding = false
            progress = 1
        }
        feedbackTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            onUnlock()
        }
    }
}

private struct DriveRecordingControls: View {
    @EnvironmentObject private var session: DriveSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showsRoute = false
    let onEnd: () -> Void
    let onLock: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(String(format: "%02d:%02d", Int(session.elapsed) / 60, Int(session.elapsed) % 60))
                    .font(.system(size: 34, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.yellow)
                HStack {
                    reading(String(format: "%.1f", session.currentDistanceMiles), "mi")
                    Spacer()
                    Button {
                        if session.isPaused { session.resumeDrive() } else { session.pauseDrive() }
                    } label: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 30, weight: .medium))
                            .frame(width: 66, height: 66)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(.white)
                    .accessibilityLabel(session.isPaused ? "Resume drive" : "Pause drive")
                    .accessibilityIdentifier("drive.controls.pauseResume")
                    Spacer()
                    reading(session.hasReliableGPS ? String(session.currentSpeedMilesPerHour) : "—", "mph")
                }
                .padding(.bottom, 2)
                control("End drive", tint: .red, action: onEnd)
                    .accessibilityIdentifier("drive.end")
                control("View route", tint: .white) { showsRoute = true }
                    .accessibilityIdentifier("drive.viewRoute")
                control("Lock controls", tint: .white, action: onLock)
                    .accessibilityIdentifier("drive.lockControls")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showsRoute) {
            NavigationStack {
                Group {
                    if session.currentRoute.count > 1 {
                        RecordedDriveMapView(route: session.currentRoute, moments: [], onSelectMoment: { _ in })
                            .ignoresSafeArea(edges: .bottom)
                    } else {
                        ContentUnavailableView("Waiting for GPS", systemImage: "location.slash", description: Text("Your recorded route appears when location data is available."))
                    }
                }
                .navigationTitle("Recorded route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsRoute = false }
                } }
            }
        }
    }

    private func reading(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(width: 68)
    }

    private func control(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body).frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(tint)
        .controlSize(.large)
    }
}
