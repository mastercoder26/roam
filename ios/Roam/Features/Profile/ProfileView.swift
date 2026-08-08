import SwiftUI
import ClerkKitUI

/// The driver's own record: who they are, what they have actually driven, and
/// the controls that belong to the person rather than to a single route or
/// drive.
///
/// Everything measured here is derived from locally recorded drives: this tab
/// introduces no network calls and stores no new measurement. The only things
/// it persists are the display name and licensing stage, both user-declared
/// and deliberately excluded from every score.
struct ProfileView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var appIcon = AppIconManager.shared
    @EnvironmentObject private var driveSession: DriveSessionManager
    @EnvironmentObject private var authSession: AuthSessionStore
    @StateObject private var profile = DriverProfileStore.shared
    @StateObject private var driveHistorySync = DriveHistorySyncService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingThemePicker = false
    @State private var showingAppIconPicker = false
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
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    profileHeader
                    identityCard

                    if driveSession.isRecording {
                        LiveDriveBanner(driveSession: driveSession)
                    }

                    profileNavigation
                    accountSection
                }
                .padding(.horizontal, AppDesign.space20)
                .padding(.vertical, AppDesign.space16)
            }
            .safeAreaPadding(.bottom, AppDesign.space24)
            .background(AppDesign.canvas.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbar(.hidden, for: .navigationBar)
        }
        .prefetchClerkImages()
        .onChange(of: insightsSignature, initial: true) { _, _ in
            refreshInsights()
        }
        // Leaving the tab mid-edit is a commit like any other. Without this,
        // a name typed but never confirmed keeps the untrimmed spacing the
        // editing rules deliberately allow through on each keystroke.
        .onDisappear {
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
        .sheet(isPresented: $authIsPresented) {
            AuthView()
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

    private var profileHeader: some View {
        ScreenHeader(
            title: "Profile",
            symbol: "person.crop.circle.fill",
            subtitle: "Your record, driven by what you've measured."
        )
    }

    // MARK: - Navigation

    private var profileNavigation: some View {
        VStack(alignment: .leading, spacing: AppDesign.space24) {
            profileFolderSection(.explore)
            profileFolderSection(.appearance)
        }
    }

    private func profileFolderSection(_ section: ProfileHomeSection) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(
                title: section.title,
                subtitle: section.subtitle
            )

            VStack(spacing: 0) {
                ForEach(section.folders) { folder in
                    NavigationLink {
                        folderDestination(folder)
                    } label: {
                        ProfileFolderCard(folder: folder, summary: folderSummary(folder))
                    }
                    .buttonStyle(PressableScaleStyle())

                    if folder != section.folders.last {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .premiumCard()
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(
                title: ProfileHomeSection.account.title,
                subtitle: ProfileHomeSection.account.subtitle
            )

            accountCard

            if isSignedIn {
                deleteAccountSection
            }
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        switch authSession.state {
        case .signedIn, .signedInOffline:
            signedInAccountCard
        case .restoring, .signedOut, .authenticating:
            signedOutAccountCard
        }
    }

    private var signedOutAccountCard: some View {
        Button {
            authIsPresented = true
        } label: {
            HStack(spacing: AppDesign.space12) {
                IconTile(symbol: "person.crop.circle.badge.plus")

                VStack(alignment: .leading, spacing: AppDesign.space4) {
                    Text("Sign in to Roam")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text("Back up your profile and saved drives.")
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppDesign.Ink.tertiary)
                    .frame(width: 24, height: 24)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .premiumCard()
        .accessibilityLabel("Sign in to Roam")
        .accessibilityHint("Back up your profile and saved drives")
    }

    private var signedInAccountCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            HStack(spacing: AppDesign.space12) {
                IconTile(symbol: "person.crop.circle.fill")

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
                .foregroundStyle(AppDesign.accent)
                .disabled(isAccountActionRunning)
            }
        }
        .padding(.vertical, AppDesign.space8)
        .premiumCard()
    }

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            SectionHeader(title: "Delete account")

            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: AppDesign.space4) {
                        Text("Delete your Roam account")
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
            .premiumCard()
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
            .padding(.vertical, 12)
        }
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

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            HStack(alignment: .top, spacing: AppDesign.space12) {
                monogram

                VStack(alignment: .leading, spacing: 2) {
                    if isEditingIdentity {
                        TextField("Add your name", text: $profile.displayName)
                            .font(AppDesign.Typography.bodyEmphasized)
                            .foregroundStyle(AppDesign.Ink.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppDesign.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppDesign.cornerRadiusSmall, style: .continuous)
                                    .stroke(AppDesign.cardStrokeStrong, lineWidth: 1)
                            }
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($focusedIdentityField, equals: .name)
                            .onSubmit {
                                profile.commitDisplayNameEdit()
                                isEditingIdentity = false
                                focusedIdentityField = nil
                            }
                    } else {
                        Text(profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add your name" : profile.resolvedDisplayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppDesign.Ink.primary)
                    }

                    Text(profile.stage.title)
                        .font(.footnote)
                        .foregroundStyle(AppDesign.Ink.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    if isEditingIdentity {
                        profile.commitDisplayNameEdit()
                        focusedIdentityField = nil
                        withAnimation(AppAnimation.quick) { isEditingIdentity = false }
                        return
                    }
                    withAnimation(AppAnimation.quick) { isEditingIdentity = true }
                    DispatchQueue.main.async {
                        focusedIdentityField = .name
                    }
                } label: {
                    Image(systemName: isEditingIdentity ? "checkmark" : "pencil")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(AppDesign.Ink.primary.opacity(0.88))
                        .frame(width: 36, height: 36)
                        .background(AppDesign.Ink.primary.opacity(0.10), in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityLabel(
                    isEditingIdentity
                        ? "Save name"
                        : (profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add your name" : "Edit name")
                )
            }

            persistenceErrorNote

            Divider()

            if insights.hasEvidence {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", insights.measuredMiles))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text("measured miles")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppDesign.Ink.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(String(format: "%.1f", insights.measuredMiles)) measured miles")
            } else {
                Text("No measured miles yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppDesign.Ink.secondary)
            }
        }
        .padding(AppDesign.space20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusHero, style: .continuous)
                .fill(AppDesign.cardSurfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: AppDesign.cornerRadiusHero, style: .continuous)
                        .fill(AppDesign.accentWash)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadiusHero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cornerRadiusHero, style: .continuous)
                .stroke(AppDesign.cardStrokeStrong, lineWidth: 0.75)
        }
        .elevation(AppDesign.Elevation.hero)
    }

    private var monogram: some View {
        Group {
            if profile.monogram.isEmpty {
                Image(systemName: "person.fill")
                    .font(.title2.weight(.semibold))
            } else {
                Text(profile.monogram)
                    .font(.title.weight(.bold))
            }
        }
        .foregroundStyle(AppDesign.accentForeground)
        .frame(width: 64, height: 64)
        .background(AppDesign.accent, in: Circle())
        .overlay {
            Circle().stroke(AppDesign.canvas, lineWidth: 3)
        }
        .elevation(AppDesign.Elevation.low)
        .accessibilityHidden(true)
    }

    /// Surfaces a failed save quietly: a small tertiary-ink caption, never an
    /// alert or a blocking banner. This is a display preference, not
    /// critical data, so it should never nag.
    @ViewBuilder
    private var persistenceErrorNote: some View {
        if let message = profile.lastPersistenceError {
            Label("Not saved on this device: \(message)", systemImage: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(AppDesign.Ink.tertiary)
                .accessibilityLabel("Your profile changes could not be saved. \(message)")
        }
    }

    // MARK: - Stage

    private var stageCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(
                title: "Licensing stage",
                subtitle: "Self-declared, and never used in a score."
            )

            ForEach(DriverProfile.Stage.allCases) { stage in
                Button {
                    withAnimation(AppAnimation.selection) { profile.stage = stage }
                } label: {
                    HStack(spacing: AppDesign.space12) {
                        Image(systemName: profile.stage == stage ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(profile.stage == stage ? AppDesign.accent : AppDesign.Ink.tertiary)
                            .contentTransition(.symbolEffect(.replace))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppDesign.Ink.primary)
                            Text(stage.detail)
                                .font(.caption)
                                .foregroundStyle(AppDesign.Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
                .accessibilityValue(profile.stage == stage ? "Selected" : "Not selected")
            }

            Divider()

            Label(profile.stage.supervisionNote, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(AppDesign.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .premiumCard()
    }

    // MARK: - Appearance

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            appearanceCard
            Divider()
                .padding(.leading, 46)
            appIconCard
        }
        .premiumCard()
    }

    private var appearanceCard: some View {
        Button {
            showingThemePicker = true
        } label: {
            HStack(spacing: AppDesign.space12) {
                IconTile(symbol: "paintpalette.fill")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Color scheme")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text(theme.currentID.title)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppDesign.Ink.tertiary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.vertical, AppDesign.space8)
        .accessibilityLabel("Color scheme, currently \(theme.currentID.title)")
    }

    private var appIconCard: some View {
        Button {
            showingAppIconPicker = true
        } label: {
            HStack(spacing: AppDesign.space12) {
                IconTile(symbol: "app.badge")

                VStack(alignment: .leading, spacing: 2) {
                    Text("App icon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppDesign.Ink.primary)
                    Text(appIcon.currentID.title)
                        .font(.caption)
                        .foregroundStyle(AppDesign.Ink.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppDesign.Ink.tertiary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.vertical, AppDesign.space8)
        .accessibilityLabel("App icon, currently \(appIcon.currentID.title)")
    }
}

#Preview {
    ProfileView()
        .environmentObject(DriveSessionManager.shared)
        .environmentObject(AuthSessionStore.shared)
}
