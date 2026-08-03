import SwiftUI

/// The driver's own record: who they are, what they have actually driven, and
/// the controls that belong to the person rather than to a single route or
/// drive.
///
/// Everything measured here is derived from locally recorded drives — this tab
/// introduces no network calls and stores no new measurement. The only things
/// it persists are the display name and licensing stage, both user-declared
/// and deliberately excluded from every score.
struct ProfileView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var driveSession: DriveSessionManager
    @StateObject private var profile = DriverProfileStore()
    @State private var showingThemePicker = false
    @State private var isEditingIdentity = false

    private var progress: DriverProgressSummary {
        DriverProgressEngine.makeSummary(from: driveSession.recordedDrives)
    }

    private var performance: DriverPerformanceSummary {
        DriverPerformanceEngine.makeSummary(from: driveSession.recordedDrives)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    identityCard
                    stageCard
                    recordCard
                    appearanceCard
                }
                .padding(AppDesign.contentPadding)
            }
            .background(AppDesign.canvas.ignoresSafeArea())
            .navigationTitle("Profile")
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerSheet(themeManager: ThemeManager.shared)
                .environmentObject(driveSession)
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        HStack(spacing: AppDesign.space12) {
            monogram

            VStack(alignment: .leading, spacing: 2) {
                if isEditingIdentity {
                    TextField("Your name", text: $profile.displayName)
                        .font(AppDesign.Typography.bodyEmphasized)
                        .foregroundStyle(AppDesign.Ink.primary)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { isEditingIdentity = false }
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
        .premiumCard()
    }

    private var monogram: some View {
        Text(profile.monogram)
            .font(.title2.weight(.bold))
            .foregroundStyle(AppDesign.accentForeground)
            .frame(width: 52, height: 52)
            .background(AppDesign.accent, in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: - Stage

    private var stageCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(
                title: "Licensing stage",
                subtitle: "Frames your own progress only. It never changes a route or drive score."
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
        }
        .premiumCard()
    }

    // MARK: - Record

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: AppDesign.space12) {
            SectionHeader(
                title: "Your record",
                subtitle: "Measured from drives recorded on this device."
            )

            if progress.hasRecordedEvidence {
                StatRow(
                    title: "Measured miles",
                    value: String(format: "%.1f mi", progress.validatedMiles),
                    symbol: "road.lanes"
                )
                StatRow(
                    title: "Qualifying drives",
                    value: "\(progress.qualifyingDriveCount)",
                    symbol: "checkmark.seal"
                )
                StatRow(
                    title: "Days driven",
                    value: "\(progress.qualifyingDriveDayCount)",
                    symbol: "calendar"
                )
                StatRow(
                    title: "After dark",
                    value: String(format: "%.1f mi", progress.afterDarkMiles),
                    symbol: "moon.stars"
                )

                if let score = performance.score {
                    StatRow(
                        title: "Driving score",
                        value: "\(score)/100",
                        symbol: "gauge.with.dots.needle.50percent"
                    )
                }
            } else {
                Text("No qualifying drives yet. Record a drive from the Drive tab and your measured experience appears here.")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
