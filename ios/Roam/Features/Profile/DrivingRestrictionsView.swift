import SwiftUI

struct DrivingRestrictionsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var profile = DriverProfileStore.shared
    @ObservedObject private var license = DrivingLicensePreferencesStore.shared
    private var summary: DrivingRestrictionSummary? {
        DrivingRestrictionsEngine.summarize(license.preferences, stage: profile.stage)
    }

    var body: some View {
        Form {
            Section("Your license") {
                Picker("US state", selection: $license.preferences.stateCode) {
                    Text("Choose state").tag("")
                    ForEach(DrivingRestrictionCatalog.states) { state in
                        Text(state.name).tag(state.id)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("profile.restrictions.state")
                Picker("License type", selection: $profile.stage) {
                    ForEach(DriverProfile.Stage.allCases) { stage in
                        Text(summary?.guide.stageTitle(stage) ?? stage.title).tag(stage)
                    }
                }
                .accessibilityIdentifier("profile.restrictions.stage")
                if license.preferences.stateCode == "NY", profile.stage != .licensed {
                    Picker("Driving region", selection: $license.preferences.newYorkRegion) {
                        Text("Choose region").tag(Optional<NewYorkDrivingRegion>.none)
                        ForEach(NewYorkDrivingRegion.allCases) { region in
                            Text(region.title).tag(Optional(region))
                        }
                    }
                    .accessibilityIdentifier("profile.restrictions.region")
                }
                NavigationLink {
                    DrivingLicenseDatesView()
                } label: {
                    LabeledContent("Age & issue date", value: datesSummary)
                }
                .accessibilityIdentifier("profile.restrictions.dates")
            }

            if let summary {
                Section {
                    ForEach(summary.rules) { rule in
                        NavigationLink {
                            AppDetailPage(title: rule.title) {
                                Text(rule.summary).font(.title2.weight(.semibold))
                                Text(rule.detail).font(.body).foregroundStyle(AppDesign.Ink.secondary)
                                if rule.kind == .passengers || rule.kind == .hours {
                                    Text("Periods assume uninterrupted, eligible driving. Violations or suspensions can extend restrictions.")
                                        .font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                                }
                                sourceLinks(summary.guide)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: rule.symbol).font(.system(size: 20)).frame(width: 24).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.title).font(.body)
                                    Text(rule.summary).font(.subheadline).foregroundStyle(AppDesign.Ink.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("profile.restrictions.\(rule.id.rawValue)")
                    }
                } header: {
                    Text(summary.guide.name)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if summary.needsAge { Text("Add your birthday to check which age rules apply.") }
                        if summary.needsIssueDate { Text("Add the original issue date to identify time-based phases.") }
                        if summary.needsRegion { Text("Choose where you drive in New York; regional restrictions differ.") }
                        Text("Standard passenger vehicles. Printed conditions, local rules and suspensions still apply.")
                    }
                }
                Section {
                    NavigationLink {
                        AppDetailPage(title: "Official sources") {
                            sourceLinks(summary.guide)
                            Text("Sources checked \(DrivingRestrictionsEngine.sourceReviewDateLabel).")
                                .font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                            Text("This is a summary of common license restrictions. Special permits, hardship licenses, commercial vehicles and out-of-state trips need a separate check with the licensing agency.")
                                .font(.footnote).foregroundStyle(AppDesign.Ink.secondary)
                        }
                    } label: { Label("Official state guide", systemImage: "arrow.up.right.square") }
                } footer: {
                    if summary.needsSourceRefresh {
                        Text("This saved guide needs a source review. Check the official state guide for current rules.")
                    }
                }
            } else {
                Section {
                    Label("Choose your state to see license restrictions.", systemImage: "person.text.rectangle")
                        .foregroundStyle(AppDesign.Ink.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppDesign.canvas)
        .tint(AppDesign.Ink.primary)
        .navigationTitle("Driving restrictions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: license.preferences.stateCode) { _, _ in clearIssueDate() }
        .onChange(of: profile.stage) { _, _ in clearIssueDate() }
    }

    private var datesSummary: String {
        guard let age = license.preferences.age(on: Date(), calendar: .current) else { return "Add details" }
        return "Age \(age)"
    }

    private func sourceLinks(_ guide: StateDrivingGuide) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(guide.sourceURLs, id: \.absoluteString) { url in
                Link(destination: url) {
                    Label(url.host() ?? "State licensing agency", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }
        }
        .tint(AppDesign.accent)
    }

    private func clearIssueDate() {
        license.preferences.issuedAt = nil
        license.preferences.issueStage = nil
        license.preferences.issueStateCode = nil
    }
}

/// The pushed form owns its observation, so changing a toggle rebuilds its date rows.
private struct DrivingLicenseDatesView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var profile = DriverProfileStore.shared
    @ObservedObject private var license = DrivingLicensePreferencesStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Add birthday", isOn: Binding(
                    get: { license.preferences.birthDate != nil },
                    set: { license.preferences.birthDate = $0 ? Calendar.current.date(byAdding: .year, value: -16, to: Date()) : nil }
                ))
                if license.preferences.birthDate != nil {
                    DatePicker("Birthday", selection: Binding(
                        get: { license.preferences.birthDate ?? Date() },
                        set: { license.preferences.birthDate = $0; clearIssueDateIfInvalid() }
                    ), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("profile.restrictions.birthday")
                }
            } footer: { Text("Age determines which teen-driver rules apply. Your birthday stays on this device.") }
            Section {
                Toggle("Add original issue date", isOn: Binding(
                    get: { license.preferences.validIssueDate(for: profile.stage, now: Date()) != nil },
                    set: { $0 ? setIssueDate(Date()) : clearIssueDate() }
                ))
                if let issue = license.preferences.validIssueDate(for: profile.stage, now: Date()) {
                    DatePicker("Issued", selection: Binding(get: { issue }, set: setIssueDate),
                               in: (license.preferences.birthDate ?? .distantPast)...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier("profile.restrictions.issuedAt")
                }
            } footer: {
                Text(license.preferences.stateCode == "DE"
                     ? "Use the original Level One permit issue date, including when selecting its solo phase. Changing your state or stage clears it."
                     : "Use the date you first received this license stage, not a renewal or replacement date. Changing your state or stage clears it.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppDesign.canvas)
        .navigationTitle("Age & issue date")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setIssueDate(_ date: Date) {
        license.preferences.issuedAt = date
        license.preferences.issueStage = profile.stage
        license.preferences.issueStateCode = license.preferences.stateCode
    }

    private func clearIssueDate() {
        license.preferences.issuedAt = nil
        license.preferences.issueStage = nil
        license.preferences.issueStateCode = nil
    }

    private func clearIssueDateIfInvalid() {
        if license.preferences.validIssueDate(for: profile.stage, now: Date()) == nil { clearIssueDate() }
    }
}
