import Foundation

@main struct DrivingRestrictionsChecks {
    static func main() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        let now = date(2026, 10, 19)
        func preferences(_ state: String, issued: Date? = nil, age: Int = 16,
                         stage: DriverProfile.Stage = .provisional) -> DrivingLicensePreferences {
            DrivingLicensePreferences(stateCode: state, birthDate: date(2026 - age, 1, 1),
                                      issuedAt: issued, issueStage: stage, issueStateCode: state)
        }
        func report(_ p: DrivingLicensePreferences, stage: DriverProfile.Stage = .provisional,
                    on: Date? = nil) -> DrivingRestrictionSummary {
            DrivingRestrictionsEngine.summarize(p, stage: stage, now: on ?? now, calendar: calendar)!
        }
        func rule(_ p: DrivingLicensePreferences, _ kind: DrivingRestriction.Kind,
                  stage: DriverProfile.Stage = .provisional, on: Date? = nil) -> DrivingRestriction {
            report(p, stage: stage, on: on).rules.first { $0.kind == kind }!
        }
        let states = DrivingRestrictionCatalog.states
        expect(states.count == 51 && Set(states.map(\.id)).count == 51, "Every state and DC must appear exactly once")
        for state in states {
            expect(!state.sourceURLs.isEmpty && state.sourceURLs.allSatisfy { $0.scheme == "https" && $0.host != nil }, "Official HTTPS source required for \(state.id)")
            expect(Set(state.sourceURLs).count == state.sourceURLs.count, "Source rows must have unique identifiers")
            for stage in DriverProfile.Stage.allCases {
                let result = report(preferences(state.id, stage: stage), stage: stage)
                expect(result.rules.count == 4 && Set(result.rules.map(\.id)).count == 4, "All rule categories must be present")
                expect(result.rules.allSatisfy { !$0.summary.isEmpty && !$0.detail.isEmpty }, "Rules must include explanations")
            }
        }
        expect(DrivingRestrictionsEngine.summarize(.init(), stage: .permit) == nil, "No default state should be guessed")
        expect(DrivingRestrictionsEngine.summarize(.init(stateCode: "ZZ"), stage: .permit) == nil, "Reject invalid state codes")

        let wa = preferences("WA", issued: date(2026, 4, 19))
        expect(rule(wa, .passengers, on: date(2026, 10, 18)).summary.contains("0 nonfamily"), "Stay in phase one until six calendar months")
        expect(rule(wa, .passengers).summary.contains("3 nonfamily"), "Switch exactly at six calendar months")
        let vt = preferences("VT", issued: date(2026, 7, 19))
        expect(rule(vt, .passengers).summary == "Family members only", "Vermont first three months must not get an early family exception")
        expect(rule(preferences("CT", issued: date(2026, 8, 1)), .passengers).summary.contains("supervisor"), "Connecticut family exception starts only in second phase")
        expect(rule(preferences("CA"), .passengers).detail.contains("not automatically exempt"), "California must retain the signed-note family condition")
        expect(rule(preferences("NJ"), .passengers).detail.contains("Siblings are not automatically exempt"), "New Jersey dependents must not mean all family")
        expect(rule(preferences("DE"), .passengers).detail.contains("only when the supervisor is present"), "Delaware family exemption is supervised only")
        expect(rule(preferences("TN"), .passengers).detail.contains("parent letter"), "Tennessee school/family documentation must remain visible")
        expect(rule(preferences("FL", age: 17, stage: .licensed), .hours, stage: .licensed).summary.contains("1–5"), "Florida regular teen licenses retain age-based curfews")
        expect(rule(preferences("NV", age: 17, stage: .licensed), .hours, stage: .licensed).summary.contains("10 PM"), "Nevada full teen license keeps curfew")
        expect(rule(preferences("DC", age: 20), .hours).summary.contains("GRAD"), "DC provisional hours continue after 18")
        expect(rule(preferences("DC", age: 17, stage: .licensed), .passengers, stage: .licensed).summary.contains("2 passengers"), "DC full-with-conditions has a different passenger cap")
        expect(rule(preferences("DC", age: 18, stage: .licensed), .passengers, stage: .licensed).summary.contains("license conditions"), "DC full license must not retain its under-18 passenger cap")
        let mdIssue = calendar.date(byAdding: .day, value: -151, to: now)!
        expect(rule(preferences("MD", issued: mdIssue), .passengers).summary.contains("period reached"), "Maryland phase is exactly 151 days")
        let inIssue = calendar.date(byAdding: .day, value: -180, to: now)!
        expect(rule(preferences("IN", issued: inIssue), .passengers).summary.contains("period reached"), "Indiana phase is exactly 180 days")

        var ny = preferences("NY")
        expect(report(ny).needsRegion, "NY must ask where the person drives")
        ny.newYorkRegion = .newYorkCity
        expect(rule(ny, .hours).summary.contains("no driving in NYC"), "A junior license cannot be used in NYC")
        ny.newYorkRegion = .longIsland
        expect(rule(ny, .supervision).summary.contains("21+"), "Long Island cannot inherit Upstate solo privileges")
        expect(rule(preferences("NY", age: 15), .hours).summary.contains("no driving"), "NY prohibits drivers under 16")
        expect(report(preferences("WA")).needsIssueDate, "Missing date must show conditional phases")
        var stale = wa
        stale.issueStage = .permit
        expect(report(stale).needsIssueDate, "A permit date cannot select a provisional phase")
        stale = wa; stale.issueStateCode = "CA"
        expect(report(stale).needsIssueDate, "A prior state date cannot select a new state phase")
        stale = wa; stale.issuedAt = date(2027, 1, 1)
        expect(report(stale).needsIssueDate, "Future issue dates are invalid")
        stale = wa; stale.issuedAt = date(2000, 1, 1)
        expect(report(stale).needsIssueDate, "Issue date before birth is invalid")
        var unknownAge = wa; unknownAge.birthDate = nil
        expect(report(unknownAge).needsAge, "Missing age cannot silently remove teen rules")
        expect(!report(wa).needsSourceRefresh, "Current reviewed sources should not be marked stale")
        expect(report(wa, on: date(2027, 10, 19)).needsSourceRefresh, "Old legal data needs a visible source refresh")
        let birthday = date(2010, 10, 20)
        var birthdayProfile = wa; birthdayProfile.birthDate = birthday
        expect(birthdayProfile.age(on: now, calendar: calendar) == 15, "Age must respect the actual birthday")
        expect(birthdayProfile.age(on: date(2026, 10, 20), calendar: calendar) == 16, "Age must update on birthday")
        expect(birthdayProfile.age(on: calendar.startOfDay(for: date(2026, 10, 20)), calendar: calendar) == 16, "Birthday must not wait for a stored time of day")
        expect(rule(wa, .passengers, on: calendar.startOfDay(for: now)).summary.contains("3 nonfamily"), "Calendar-month phases change at the start of the anniversary date")

        await MainActor.run {
            let suite = "roam.restrictions.checks.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = DrivingLicensePreferencesStore(defaults: defaults)
            store.preferences = wa
            expect(DrivingLicensePreferencesStore(defaults: defaults).preferences == wa, "Preferences must persist")
            store.reset()
            expect(defaults.object(forKey: DrivingLicensePreferencesStore.storageKey) == nil, "Reset must erase birthday and license dates")
            expect(store.preferences == .init(), "Reset must clear the in-memory identity too")
            expect(AccountLocalDataBoundary.contentKeys.contains(DrivingLicensePreferencesStore.storageKey), "The account boundary must clear restrictions preferences")
        }
        print("Driving restrictions checks passed")
    }
}
