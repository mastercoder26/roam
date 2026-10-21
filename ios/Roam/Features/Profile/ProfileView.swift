import SwiftUI
import ClerkKitUI

/// The driver's own record: who they are, what they have actually driven, and
/// the controls that belong to the person rather than to a single route or
/// drive.
///
/// Everything measured here is derived from locally recorded drives: this tab
/// introduces no network calls and stores no new measurement. Identity stays
/// user-declared and excluded from every score; artwork selection is only a
/// local display preference.
struct ProfileView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var appIcon = AppIconManager.shared
    @EnvironmentObject private var driveSession: DriveSessionManager
    @EnvironmentObject private var authSession: AuthSessionStore
    @ObservedObject private var profile = DriverProfileStore.shared
    @ObservedObject private var driveHistorySync = DriveHistorySyncService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("roam.profile-landscape-v1") private var lastLandscape = ""
    @State private var landscape: ProfileLandscape = .valley
    @State private var isProfileVisible = false
    @State private var didEnterBackground = false

    @State private var showingThemePicker = false
    @State private var showingAppIconPicker = false
    @State private var showingFeatureWalkthrough = false
    @State private var showingDeleteConfirmation = false
    @State private var authIsPresented = false
    @State private var accountError: String?
    @State private var isAccountActionRunning = false
    @State private var isEditingIdentity = false
    @State private var insights = DriverProfileInsightsEngine.makeInsights(from: [], stage: .permit)
    @FocusState private var focusedIdentityField: IdentityField?

    private enum IdentityField: Hashable {
        case name
    }

    private static let scrollSpace = "profile.scroll"

    /// A cheap fingerprint of everything that can change the aggregated
    /// insights: drive count, the most recent drive's identity, each drive's
    /// route analysis status, and the declared stage.
    /// `DriverProfileInsightsEngine.makeInsights` walks the full drive
    /// history, so gating the recompute on this instead of running it as a
    /// computed property keeps typing a name or switching themes from
    /// re-running that aggregation on every body evaluation.
    ///
    /// Combining each drive's `routeAnalysis?.status` (not just whether it is
    /// non-nil) matters: a drive's analysis starts as a non-nil `.pending`
    /// value, and the Drive tab's background retry later flips that same
    /// non-nil value to `.available` or `.unavailable`. A presence check
    /// alone would miss that transition, since the field never becomes nil
    /// either before or after it resolves, leaving `performanceScore`,
    /// `averageDifficulty`, `analyzedDriveCount`, and `pendingAnalysisCount`
    /// stale on the Profile tab until some unrelated state change forced a
    /// refresh. This still stays O(n) over already-loaded values, never a
    /// second heavy aggregation.
    private var insightsSignature: Int {
        var hasher = Hasher()
        hasher.combine(driveSession.recordedDrives.count)
        hasher.combine(driveSession.recordedDrives.last?.id)
        hasher.combine(driveSession.recordedDrives.last?.startedAt)
        for drive in driveSession.recordedDrives {
            hasher.combine(drive.routeAnalysis?.status)
        }
        hasher.combine(profile.stage)
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        profileHeader(topInset: geometry.safeAreaInsets.top)

                        VStack(alignment: .leading, spacing: 28) {
                            if driveSession.isRecording {
                                LiveDriveBanner(driveSession: driveSession)
                            }
                            profileNavigation
                            if isSignedIn { accountSection }
                        }
                        .padding(.horizontal, AppDesign.contentPadding)
                        .padding(.bottom, AppDesign.space24)
                        .frame(maxWidth: AppDesign.maximumContentWidth)
                        .frame(maxWidth: .infinity)
                    }
                }
                .contentMargins(.bottom, AppDesign.tabBarClearance, for: .scrollContent)
                .coordinateSpace(name: Self.scrollSpace)
                .scrollBounceBehavior(.always, axes: .vertical)
                .ignoresSafeArea(.container, edges: .top)
                .background(profileCanvas.ignoresSafeArea())
            }
            .navigationTitle("Profile")
            .toolbar(.hidden, for: .navigationBar)
        }
        .prefetchClerkImages()
        .onAppear {
            isProfileVisible = true
            didEnterBackground = false
            refreshLandscape()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { didEnterBackground = true }
            if phase == .active && didEnterBackground && isProfileVisible {
                didEnterBackground = false
                refreshLandscape()
            }
        }
        .onChange(of: insightsSignature, initial: true) { _, _ in
            refreshInsights()
        }
        // Leaving the tab mid-edit is a commit like any other. Without this,
        // a name typed but never confirmed keeps the untrimmed spacing the
        // editing rules deliberately allow through on each keystroke.
        .onDisappear {
            isProfileVisible = false
            guard isEditingIdentity else { return }
            profile.commitDisplayNameEdit()
            isEditingIdentity = false
            focusedIdentityField = nil
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerSheet(themeManager: theme)
                .environmentObject(driveSession)
        }
        .sheet(isPresented: $showingAppIconPicker) {
            AppIconPickerSheet(iconManager: appIcon)
        }
        .sheet(isPresented: $showingFeatureWalkthrough) {
            FeatureWalkthroughSheet()
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
        .sheet(isPresented: $isEditingIdentity, onDismiss: {
            profile.commitDisplayNameEdit()
            focusedIdentityField = nil
        }) {
            identityEditor
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete your Roam account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your server account and synced profile. Your local drives stay, but the local profile fields are cleared.")
        }
    }

    private func refreshInsights() {
        insights = DriverProfileInsightsEngine.makeInsights(
            from: driveSession.recordedDrives,
            stage: profile.stage
        )
    }

    private var profileCanvas: Color {
        theme.preferredColorScheme == .dark ? .black : AppDesign.canvas
    }

    private func refreshLandscape() {
        landscape = ProfileLandscape.next(excluding: lastLandscape)
        lastLandscape = landscape.rawValue
    }

    private func profileHeader(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Color.clear.frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Text("Profile")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button(action: refreshLandscape) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .profileGlassSurface(cornerRadius: 22)
                        .environment(\.colorScheme, .dark)
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityLabel("Change landscape")
                .accessibilityIdentifier("profile.refreshLandscape")
            }

            Text(isSignedIn ? profile.snapshot.greeting : "Welcome")
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(AppDesign.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, 22)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("profile.greeting")

            if isSignedIn {
                ProfileDrivingSummary(insights: insights)
                    .padding(.bottom, 22)
            }

            heroAccountCard
            persistenceErrorNote
        }
        .padding(.horizontal, AppDesign.contentPadding)
        .padding(.top, topInset + 8)
        .padding(.bottom, 28)
        .frame(maxWidth: AppDesign.maximumContentWidth)
        .frame(maxWidth: .infinity)
        .profileGlassContainer()
        .background {
            GeometryReader { geometry in
                let pull = ProfileHeaderPull(
                    offset: geometry.frame(in: .named(Self.scrollSpace)).minY,
                    reduceMotion: reduceMotion
                )
                Image(landscape.rawValue)
                    .resizable()
                    .scaledToFill()
                    // Extra image bleed keeps blurred edges filled while
                    // the header remains anchored to the top of the screen.
                    .frame(
                        width: geometry.size.width + pull.blurRadius * 4,
                        height: geometry.size.height + pull.expansion + pull.blurRadius * 4
                    )
                    .blur(radius: pull.blurRadius, opaque: true)
                    .frame(width: geometry.size.width, height: geometry.size.height + pull.expansion)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.08), location: 0),
                                .init(color: profileCanvas.opacity(0.10), location: 0.22),
                                .init(color: profileCanvas.opacity(0.38), location: 0.40),
                                .init(color: profileCanvas.opacity(0.80), location: 0.70),
                                .init(color: profileCanvas, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipped()
                    .offset(y: pull.verticalOffset)
                    .accessibilityHidden(true)
            }
        }
    }

    private func profileSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: - Navigation

    private var profileNavigation: some View {
        VStack(alignment: .leading, spacing: 28) {
            profileFolderSection(.explore)
            profileSection("Preferences") { preferencesCard }
            profileSection("Help") { walkthroughCard.profileSettingsSurface() }
        }
    }

    private func profileFolderSection(_ section: ProfileHomeSection) -> some View {
        profileSection(section == .explore ? "Driving" : "Preferences") {
            VStack(spacing: 0) {
                if !isSignedIn {
                    Button { isEditingIdentity = true } label: {
                        ProfileSettingsRow(title: "Driver profile", symbol: "person.crop.circle")
                    }
                    .buttonStyle(PressableScaleStyle())
                    .accessibilityHint("Edit your name and licensing stage on this device")
                    .accessibilityIdentifier("profile.editIdentity")
                    Divider().padding(.leading, AppDesign.Menu.dividerInset)
                }
                ForEach(section.folders) { folder in
                    NavigationLink {
                        folderDestination(folder)
                    } label: {
                        ProfileSettingsRow(title: folder.title, symbol: folder.symbol)
                    }
                    .buttonStyle(PressableScaleStyle())
                    .accessibilityHint(folderSummary(folder))

                    if folder != section.folders.last {
                        Divider()
                            .padding(.leading, AppDesign.Menu.dividerInset)
                    }
                }
                if section == .explore {
                    Divider().padding(.leading, AppDesign.Menu.dividerInset)
                    NavigationLink { DrivingRestrictionsView() } label: {
                        ProfileSettingsRow(title: "Driving restrictions", symbol: "person.text.rectangle")
                    }
                    .buttonStyle(PressableScaleStyle())
                    .accessibilityIdentifier("profile.drivingRestrictions")
                }
            }
            .profileSettingsSurface()
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            Text("Account")
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            signedInAccountCard

            if isSignedIn {
                deleteAccountSection
            }
        }
    }

    private var signedInAccountCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            HStack(spacing: AppDesign.space12) {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(AppDesign.Ink.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppDesign.space4) {
                    Text(accountDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text(authSession.currentUser?.email.isEmpty == false ? authSession.currentUser?.email ?? "" : "Signed in")
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                }

                Spacer(minLength: AppDesign.space8)
            }

            Divider()

            syncStatusRow
            driveHistorySyncStatusRow

            if let accountError {
                Text(accountError)
                    .font(.caption)
                    .foregroundStyle(AppDesign.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                Divider()

                Button(action: signOut) {
                    HStack {
                        Text("Sign out")
                        Spacer()
                        if isAccountActionRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .foregroundStyle(AppDesign.danger)
                .disabled(isAccountActionRunning)
            }
        }
        .padding(16)
        .profileSettingsSurface()
    }

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: AppDesign.space4) {
                        Text("Delete account")
                            .font(.subheadline.weight(.semibold))
                        Text("This cannot be undone. Your local drives stay on this device.")
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: AppDesign.space8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle())
            .foregroundStyle(AppDesign.danger)
            .disabled(isAccountActionRunning)
            .padding(16)
            .profileSettingsSurface()
        }
    }

    private var isSignedIn: Bool {
        switch authSession.state {
        case .signedIn, .signedInOffline: true
        case .restoring, .signedOut, .authenticating: false
        }
    }

    private var syncStatusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: syncStatusSymbol)
                .foregroundStyle(syncStatusColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(syncStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text(syncStatusDetail)
                    .font(.caption2)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if case .failed = authSession.syncStatus {
                Button("Retry") {
                    Task { await authSession.retryProfileSync() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(syncStatusTitle). \(syncStatusDetail)")
    }

    private var driveHistorySyncStatusRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: driveHistorySyncSymbol)
                .foregroundStyle(driveHistorySyncColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(driveHistorySyncTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.primary)
                Text(driveHistorySyncDetail)
                    .font(.caption2)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if case .failed = driveHistorySync.state {
                Button("Retry") {
                    authSession.requestDriveHistorySync()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppDesign.accent)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(driveHistorySyncTitle). \(driveHistorySyncDetail)")
    }

    private var accountDisplayName: String {
        guard let displayName = authSession.currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty else {
            return "Your Roam account"
        }
        return displayName
    }

    private var syncStatusTitle: String {
        switch authSession.syncStatus {
        case .synced: "Synced"
        case .syncing: "Syncing profile"
        case .workingOffline: "Working offline"
        case .failed: "Sync failed"
        }
    }

    private var syncStatusDetail: String {
        switch authSession.syncStatus {
        case .synced: "Your profile is up to date."
        case .syncing: "Saving your profile changes."
        case .workingOffline: "Changes will sync when you are back."
        case .failed(let message): message
        }
    }

    private var syncStatusSymbol: String {
        switch authSession.syncStatus {
        case .synced: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .workingOffline: "wifi.slash"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var syncStatusColor: Color {
        switch authSession.syncStatus {
        case .synced: AppDesign.positive
        case .syncing: AppDesign.accent
        case .workingOffline: AppDesign.Ink.secondary
        case .failed: AppDesign.danger
        }
    }

    private var driveHistorySyncTitle: String {
        switch driveHistorySync.state {
        case .idle: "Drive history ready"
        case .syncing: "Syncing drive history"
        case .synced: "Drive history synced"
        case .offline: "Working offline"
        case .failed: "Drive history sync failed"
        }
    }

    private var driveHistorySyncDetail: String {
        switch driveHistorySync.state {
        case .idle: "Your saved drives stay available on this device."
        case .syncing: "Your local drives remain available while Roam syncs."
        case .synced: "Your saved drives are backed up for this account."
        case .offline: "Your local drives are queued and will retry when you are back online."
        case .failed(let message): message
        }
    }

    private var driveHistorySyncSymbol: String {
        switch driveHistorySync.state {
        case .idle: "internaldrive"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle.fill"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var driveHistorySyncColor: Color {
        switch driveHistorySync.state {
        case .idle: AppDesign.Ink.secondary
        case .syncing: AppDesign.accent
        case .synced: AppDesign.positive
        case .offline: AppDesign.Ink.secondary
        case .failed: AppDesign.danger
        }
    }

    private func deleteAccount() {
        isAccountActionRunning = true
        accountError = nil
        Task {
            do {
                try await authSession.deleteAccount()
            } catch {
                accountError = error.localizedDescription
            }
            isAccountActionRunning = false
        }
    }

    private func signOut() {
        isAccountActionRunning = true
        accountError = nil
        Task {
            do {
                try await authSession.signOut()
            } catch {
                accountError = error.localizedDescription
            }
            isAccountActionRunning = false
        }
    }

    @ViewBuilder
    private func folderDestination(_ folder: ProfileFolder) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                switch folder {
                case .progress:
                    measuredExperience
                    WeekCadenceStrip(
                        title: "Driving rhythm",
                        days: CadenceDay.recentWeek(completedDates: driveSession.recordedDrives.map(\.startedAt))
                    )
                    MilestonesSection(milestones: insights.milestones)
                    stageCard
                case .drivingInsights:
                    ExperienceBreakdownSection(insights: insights)
                    BehaviorSignalsSection(insights: insights)
                    WeeklyTrendSection(insights: insights, reduceMotion: reduceMotion)
                case .preferences:
                    preferencesCard
                }
            }
            .padding(.horizontal, AppDesign.contentPadding)
            .padding(.top, AppDesign.space16)
            .padding(.bottom, AppDesign.space24)
            .frame(maxWidth: AppDesign.maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.bottom, AppDesign.tabBarClearance, for: .scrollContent)
        .background(AppDesign.canvas.ignoresSafeArea())
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func folderSummary(_ folder: ProfileFolder) -> String {
        switch folder {
        case .progress:
            let complete = insights.milestones.filter(\.isComplete).count
            return "\(complete) of \(insights.milestones.count) goals complete"
        case .drivingInsights:
            guard insights.hasEvidence else { return "Ready after your first recorded drive" }
            return "\(insights.qualifyingDriveCount) qualifying \(insights.qualifyingDriveCount == 1 ? "drive" : "drives") recorded"
        case .preferences:
            return "\(theme.currentID.title) · \(appIcon.currentID.title) icon"
        }
    }

    // MARK: - Identity

    @ViewBuilder
    private var heroAccountCard: some View {
        switch authSession.state {
        case .signedIn, .signedInOffline:
            identityCard
        case .signedOut:
            Button { authIsPresented = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 26, weight: .regular))
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sign in to Roam")
                            .font(.body.weight(.semibold))
                        Text("Back up your profile and drives.")
                            .font(.subheadline)
                            .opacity(0.72)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.6)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(AppDesign.Ink.primary)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .profileGlassSurface(cornerRadius: 28)
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel("Sign in to Roam")
            .accessibilityHint("Back up your profile and drives. You can keep using Roam without signing in.")
            .accessibilityIdentifier("profile.signIn")
        case .restoring, .authenticating:
            HStack(spacing: 14) {
                ProgressView()
                Text(authSession.state == .restoring ? "Restoring account" : "Signing in")
                    .font(.body)
            }
            .foregroundStyle(AppDesign.Ink.primary)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .profileGlassSurface(cornerRadius: 28)
        }
    }

    private var identityCard: some View {
        Button {
            isEditingIdentity = true
        } label: {
            HStack(spacing: 14) {
                monogram
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.resolvedDisplayName)
                        .font(.body.weight(.semibold))
                    Text("Edit profile")
                        .font(.subheadline)
                        .opacity(0.72)
                }
                .foregroundStyle(AppDesign.Ink.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .profileGlassSurface(cornerRadius: 28)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("\(profile.resolvedDisplayName), edit profile")
        .accessibilityHint("Edit your name and licensing stage")
        .accessibilityIdentifier("profile.editIdentity")
    }

    private var identityEditor: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    profileSection("Name") {
                        TextField("Your name", text: $profile.displayName)
                            .font(.body)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($focusedIdentityField, equals: .name)
                            .onSubmit { profile.commitDisplayNameEdit() }
                            .padding(16)
                            .profileSettingsSurface()
                            .accessibilityLabel("Your name")
                            .accessibilityIdentifier("profile.displayName")
                    }
                    persistenceErrorNote
                    stageCard
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.top, AppDesign.space16)
                .padding(.bottom, AppDesign.space24)
                .frame(maxWidth: AppDesign.maximumContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(AppDesign.canvas.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        profile.commitDisplayNameEdit()
                        focusedIdentityField = nil
                        isEditingIdentity = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var monogram: some View {
        Group {
            if profile.monogram.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .medium))
            } else {
                Text(profile.monogram)
                    .font(.system(size: 24, weight: .medium))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.black.opacity(0.76))
        .frame(width: 52, height: 52)
        .background(
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.84, blue: 0.79), Color(red: 0.72, green: 0.64, blue: 0.71)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Circle()
        )
        .accessibilityHidden(true)
    }

    private var measuredExperience: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            Text("Measured miles")
                .font(.subheadline)
                .foregroundStyle(AppDesign.Ink.secondary)
            if insights.hasEvidence {
                Text(String(format: "%.1f", insights.measuredMiles))
                    .font(AppDesign.Typography.display)
                    .monospacedDigit()
                Text("\(insights.qualifyingDriveCount) qualifying \(insights.qualifyingDriveCount == 1 ? "drive" : "drives")")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
            } else {
                Text("No drives yet")
                    .font(.title2.weight(.semibold))
                Text("Record a drive to start building your measured experience.")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(AppDesign.Ink.primary)
        .heroCard()
    }

    /// Surfaces a failed save quietly: a small tertiary-ink caption, never an
    /// alert or a blocking banner. This is a display preference, not
    /// critical data, so it should never nag.
    @ViewBuilder
    private var persistenceErrorNote: some View {
        if let message = profile.lastPersistenceError {
            Label("Not saved on this device: \(message)", systemImage: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(AppDesign.Ink.secondary)
                .accessibilityLabel("Your profile changes could not be saved. \(message)")
        }
    }

    // MARK: - Stage

    private var stageCard: some View {
        profileSection("Licensing stage") {
            VStack(spacing: 0) {
                ForEach(DriverProfile.Stage.allCases) { stage in
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : AppAnimation.selection) {
                            profile.stage = stage
                        }
                    } label: {
                        AppSelectionRow(title: stage.title, detail: stage.detail, isSelected: profile.stage == stage) {
                            EmptyView()
                        }
                    }
                    .buttonStyle(PressableScaleStyle())
                    .accessibilityLabel(stage.title)
                    .accessibilityValue(profile.stage == stage ? "Selected" : "Not selected")
                    .accessibilityHint(stage.detail)
                    .accessibilityIdentifier("profile.stage.\(stage.id)")

                    if stage != DriverProfile.Stage.allCases.last {
                        Divider().padding(.leading, AppDesign.contentPadding)
                    }
                }
            }
            .menuSurface()

            Text("Self-declared and never used in a score. \(profile.stage.supervisionNote)")
                .font(.footnote)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppDesign.space4)
        }
    }

    // MARK: - Appearance

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            appearanceCard
            Divider()
                .padding(.leading, AppDesign.Menu.dividerInset)
            appIconCard
        }
        .profileSettingsSurface()
    }

    private var walkthroughCard: some View {
        Button {
            showingFeatureWalkthrough = true
        } label: {
            ProfileSettingsRow(title: "Explore Roam", symbol: "map")
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("Explore Roam")
        .accessibilityHint("Opens a quick guide to every Roam feature")
        .accessibilityIdentifier("settings.startWalkthrough")
    }

    private var appearanceCard: some View {
        Button {
            showingThemePicker = true
        } label: {
            ProfileSettingsRow(title: "Appearance", symbol: "circle.lefthalf.filled", value: theme.currentID.title)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("Color scheme, currently \(theme.currentID.title)")
    }

    private var appIconCard: some View {
        Button {
            showingAppIconPicker = true
        } label: {
            ProfileSettingsRow(title: "App icon", symbol: "app", value: appIcon.currentID.title)
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel("App icon, currently \(appIcon.currentID.title)")
    }
}

#Preview {
    ProfileView()
        .environmentObject(DriveSessionManager.shared)
        .environmentObject(AuthSessionStore.shared)
}

#if DEBUG
/// A read-only layout fixture. It owns an isolated session, never restores
/// Clerk credentials, and never starts account or drive-history sync.
struct ProfileSignedInPreview: View {
    @StateObject private var session: AuthSessionStore

    init() {
        let session = AuthSessionStore(automaticallyRestore: false)
        session.setSignedInForTesting(
            user: AuthUser(id: "profile-layout-preview", email: "", displayName: nil),
            accessToken: ""
        )
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        ProfileView()
            .environmentObject(DriveSessionManager.shared)
            .environmentObject(session)
            .allowsHitTesting(false)
    }
}
#endif
