import SwiftUI

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
    @EnvironmentObject private var driveSession: DriveSessionManager
    @StateObject private var profile = DriverProfileStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingThemePicker = false
    @State private var isEditingIdentity = false
    @State private var insights = DriverProfileInsightsEngine.makeInsights(from: [], stage: .permit)

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
                    identityCard

                    if driveSession.isRecording {
                        LiveDriveBanner(driveSession: driveSession)
                    }

                    HeadlineMeasurementCard(insights: insights)
                    MilestonesSection(milestones: insights.milestones)
                    ExperienceBreakdownSection(insights: insights)
                    BehaviorSignalsSection(insights: insights)
                    WeeklyTrendSection(insights: insights, reduceMotion: reduceMotion)
                    stageCard
                    appearanceCard
                }
                .padding(.horizontal, AppDesign.contentPadding)
                .padding(.vertical, 12)
            }
            .background(AppDesign.canvas.ignoresSafeArea())
            .navigationTitle("Profile")
            // Matches every other tab. Left at the default, the title mode can
            // resolve differently after a tab switch than it does on first
            // appearance, so it is stated explicitly here.
            .navigationBarTitleDisplayMode(.large)
        }
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
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerSheet(themeManager: theme)
                .environmentObject(driveSession)
        }
    }

    private func refreshInsights() {
        insights = DriverProfileInsightsEngine.makeInsights(
            from: driveSession.recordedDrives,
            stage: profile.stage
        )
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space8) {
            HStack(spacing: AppDesign.space12) {
                monogram

                VStack(alignment: .leading, spacing: 2) {
                    if isEditingIdentity {
                        TextField("Your name", text: $profile.displayName)
                            .font(AppDesign.Typography.bodyEmphasized)
                            .foregroundStyle(AppDesign.Ink.primary)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit {
                                profile.commitDisplayNameEdit()
                                isEditingIdentity = false
                            }
                    } else {
                        Text(profile.resolvedDisplayName)
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
                    }
                    withAnimation(AppAnimation.quick) { isEditingIdentity.toggle() }
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
                .accessibilityLabel(isEditingIdentity ? "Save name" : "Edit name")
            }

            persistenceErrorNote
        }
        .premiumCard()
    }

    private var monogram: some View {
        Group {
            if profile.monogram.isEmpty {
                Image(systemName: "person.fill")
                    .font(.title3.weight(.semibold))
            } else {
                Text(profile.monogram)
                    .font(.title2.weight(.bold))
            }
        }
        .foregroundStyle(AppDesign.accentForeground)
        .frame(width: 52, height: 52)
        .background(AppDesign.accent, in: Circle())
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
                subtitle: "Your own progress only."
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
        .premiumCard()
        .accessibilityLabel("Color scheme, currently \(theme.currentID.title)")
    }
}

#Preview {
    ProfileView()
        .environmentObject(DriveSessionManager.shared)
}
