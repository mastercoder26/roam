import Foundation

enum NewYorkDrivingRegion: String, CaseIterable, Codable, Identifiable {
    case upstate, newYorkCity, longIsland
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upstate: "Upstate New York"
        case .newYorkCity: "New York City"
        case .longIsland: "Long Island"
        }
    }
}

/// These preferences stay on the device and never enter the public driver profile.
struct DrivingLicensePreferences: Codable, Equatable {
    var stateCode = ""
    var birthDate: Date?
    var issuedAt: Date?
    var issueStage: DriverProfile.Stage?
    var issueStateCode: String?
    var newYorkRegion: NewYorkDrivingRegion?

    func validIssueDate(for stage: DriverProfile.Stage, now: Date, calendar: Calendar = .current) -> Date? {
        guard issueStage == stage, issueStateCode == stateCode,
              let issuedAt, calendar.startOfDay(for: issuedAt) <= calendar.startOfDay(for: now),
              birthDate.map({ calendar.startOfDay(for: issuedAt) >= calendar.startOfDay(for: $0) }) ?? true else { return nil }
        return issuedAt
    }

    func age(on date: Date, calendar: Calendar) -> Int? {
        guard let birthDate, calendar.startOfDay(for: birthDate) <= calendar.startOfDay(for: date) else { return nil }
        return calendar.dateComponents([.year], from: calendar.startOfDay(for: birthDate), to: calendar.startOfDay(for: date)).year
    }
}

struct DrivingRestriction: Identifiable, Equatable {
    enum Kind: String { case hours, passengers, supervision, other }
    let kind: Kind
    let summary: String
    let detail: String
    var id: Kind { kind }
    var title: String {
        switch kind {
        case .hours: "Driving hours"
        case .passengers: "Passengers"
        case .supervision: "Supervision"
        case .other: "Other conditions"
        }
    }
    var symbol: String {
        switch kind {
        case .hours: "moon"
        case .passengers: "person.2"
        case .supervision: "person.crop.circle.badge.checkmark"
        case .other: "checkmark.shield"
        }
    }
}

struct StateDrivingGuide: Identifiable {
    let id: String
    let name: String
    let sources: [String]
    let permitSupervisor: String
    let permitConditions: String
    let teenAgeLimit: Int
    let night: String
    let nightExceptions: String
    let passengers: String
    let passengerExceptions: String
    let other: String
    /// Some states call a teen credential a full license. Age rules still apply.
    var ageRulesOnFullLicense = false
    var sourceURLs: [URL] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0).inserted }.compactMap(URL.init(string:))
    }

    func stageTitle(_ stage: DriverProfile.Stage) -> String {
        let titles: [String]?
        switch id {
        case "MI": titles = ["Level 1 learner", "Level 2 intermediate", "Level 3 full license"]
        case "NC": titles = ["Level 1 learner", "Level 2 limited provisional", "Level 3 full provisional"]
        case "WV": titles = ["Level 1 instruction", "Level 2 intermediate", "Level 3 full license"]
        case "DE": titles = ["Level One, supervised phase", "Level One, solo phase", "Full Class D license"]
        case "SD": titles = ["Instruction permit", "Restricted minor permit", "Operator license"]
        case "NH": titles = ["Supervised learning", "Youth Operator license", "Full operator license"]
        case "NJ": titles = ["Learner / examination permit", "Probationary license", "Basic license"]
        case "GA": titles = ["Class CP learner permit", "Class D provisional", "Class C license"]
        case "NY": titles = ["Learner permit", "Junior license (Class DJ)", "Adult license (Class D)"]
        case "MA": titles = ["Learner’s permit", "Junior Operator license", "Full license"]
        case "PA": titles = ["Learner’s permit", "Junior license", "Unrestricted license"]
        case "SC": titles = ["Beginner’s permit", "Conditional / special restricted", "Full driving privileges"]
        case "IN": titles = ["Learner’s permit", "Probationary license", "Full license"]
        case "IL": titles = ["Instruction permit", "Initial license", "Full license"]
        case "KS": titles = ["Instruction permit", "Restricted license", "Nonrestricted license"]
        default: titles = nil
        }
        guard let titles else { return stage.title }
        return titles[stage == .permit ? 0 : stage == .provisional ? 1 : 2]
    }
}

struct DrivingRestrictionSummary {
    let guide: StateDrivingGuide
    let rules: [DrivingRestriction]
    let context: String
    let needsAge: Bool
    let needsIssueDate: Bool
    let needsRegion: Bool
    let needsSourceRefresh: Bool
}

enum DrivingRestrictionsEngine {
    static let sourceReviewDate = Date(timeIntervalSince1970: 1_792_368_000) // 2026-10-19 UTC
    static let sourceReviewDateLabel = "Oct 19, 2026"

    static func summarize(_ preferences: DrivingLicensePreferences, stage: DriverProfile.Stage,
                          now: Date = Date(), calendar: Calendar = .current) -> DrivingRestrictionSummary? {
        guard let guide = DrivingRestrictionCatalog.states.first(where: { $0.id == preferences.stateCode }) else { return nil }
        let age = preferences.age(on: now, calendar: calendar)
        let issue = preferences.validIssueDate(for: stage, now: now, calendar: calendar)
        let days = issue.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0 }
        func beforeMonths(_ months: Int) -> Bool? {
            issue.flatMap { calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: $0)) }.map { now < $0 }
        }
        var night = guide.night
        var passengers = guide.passengers
        var nightDetail = guide.nightExceptions
        var passengerDetail = guide.passengerExceptions
        var supervision = "Solo driving, within limits"
        var supervisionDetail = "Night and passenger exceptions may require a particular supervising adult. Check the exceptions before driving."
        var other = guide.other
        let ageLimit = guide.id == "DC" && stage == .licensed ? 18 : guide.teenAgeLimit
        let isTeen = age.map { $0 < ageLimit } ?? true
        let teenLicense = stage == .provisional || (stage == .licensed && guide.ageRulesOnFullLicense)

        // An issue date selects an elapsed-time phase, never grants a new credential.
        // Suspensions and violations can extend a phase; the UI says so explicitly.
        if teenLicense && isTeen {
            if guide.id == "AR" {
                supervision = "Solo only after 6 months’ experience"
                supervisionDetail = guide.permitSupervisor
            }
            switch guide.id {
            case "GA":
                if let first = beforeMonths(6), let year = beforeMonths(12) {
                    passengers = first ? "Immediate family only" : year ? "1 nonfamily passenger under 21" : "3 nonfamily passengers under 21"
                }
            case "CO", "CT", "OR", "WA", "WV", "MN", "MO", "MT", "PA", "VT", "SD":
                if let first = beforeMonths(6) {
                    switch guide.id {
                    case "CO": passengers = first ? "0 passengers under 21" : (beforeMonths(12) == true ? "1 passenger under 21" : "12-month period reached")
                    case "CT": passengers = first ? "Parents or qualified supervisor only" : (beforeMonths(12) == true ? "Immediate family + supervisor" : "12-month period reached")
                    case "OR", "WA": passengers = first ? "0 nonfamily passengers under 20" : (beforeMonths(12) == true ? "3 nonfamily passengers under 20" : "12-month period reached")
                    case "WV": passengers = first ? "0 nonfamily passengers under 20" : (beforeMonths(12) == true ? "1 nonfamily passenger under 20" : "Check Level 3 eligibility")
                    case "MN": passengers = first ? "1 nonfamily passenger under 20" : (beforeMonths(12) == true ? "3 nonfamily passengers under 20" : "12-month period reached")
                    case "MO": passengers = first ? "1 nonfamily passenger under 19" : "3 nonfamily passengers under 19"
                    case "MT": passengers = first ? "1 unrelated passenger under 18" : (beforeMonths(12) == true ? "3 unrelated passengers under 18" : "Check restriction end date")
                    case "PA": passengers = first ? "1 nonfamily passenger under 18" : "Up to 3, with a clean record"
                    case "SD": passengers = first ? "Family or household only" : "1 outside family or household"
                    case "VT": passengers = beforeMonths(3) == true ? "Supervisor required for any passengers" : first ? "Family members only" : "6-month period reached"
                    default: break
                    }
                }
            case "CA", "IL", "NV", "NH", "MA", "UT", "NE", "MD", "WI", "ME", "ID", "RI", "AZ":
                let ended: Bool?
                switch guide.id {
                case "MD": ended = days.map { $0 >= 151 }
                case "ME": ended = days.map { $0 >= 270 }
                case "WI": ended = beforeMonths(9).map { !$0 }
                case "CA", "IL", "RI": ended = beforeMonths(12).map { !$0 }
                default: ended = beforeMonths(6).map { !$0 }
                }
                if ended == true { passengers = "Initial passenger period reached" }
            case "DE":
                if beforeMonths(6) == true {
                    supervision = "Supervisor required every drive"
                    supervisionDetail = "The first six months of a Level One permit are supervised. Family passengers are excepted only while a supervisor is present."
                }
            case "IN":
                if let days, days >= 180 {
                    passengers = "Initial passenger period reached"
                    night = "Under 18: 11 PM / 1 AM–5 AM"
                }
            case "OH":
                if beforeMonths(12) == false { night = "No solo driving 1–5 AM"; passengers = "First-year passenger period reached" }
            default: break
            }
            // Nighttime phases do not always match passenger phases.
            switch guide.id {
            case "CA", "CO", "OR", "WA":
                if beforeMonths(12) == false { night = "Initial night-driving period reached" }
            case "MN": if beforeMonths(6) == false { night = "Initial night-driving period reached" }
            case "AZ": if beforeMonths(6) == false { night = "Initial night-driving period reached" }
            case "WI": if beforeMonths(9) == false { night = "Initial night-driving period reached" }
            case "ME": if let days, days >= 270 { night = "270-day period reached" }
            case "FL":
                if age == 16 { night = "No solo driving 11 PM–6 AM" }
                if age == 17 { night = "No solo driving 1–5 AM" }
            case "ID": if let age, age >= 16 { night = "Under-16 night rule no longer applies" }
            case "ND": if let age, age >= 16 { night = "Under-16 night rule no longer applies" }
            default: break
            }
            if guide.id == "DC", stage == .licensed {
                passengers = "2 passengers under 21, excluding siblings"
            }
        }

        let needsRegion = guide.id == "NY" && age.map({ $0 < 18 }) != false && stage != .licensed && preferences.newYorkRegion == nil
        if guide.id == "NY", isTeen, stage == .provisional {
            switch preferences.newYorkRegion {
            case .newYorkCity:
                night = "Junior license: no driving in NYC"
                passengers = "Driving is not permitted"
                supervision = "Supervisor does not waive NYC ban"
                nightDetail = "A Class DJ junior license cannot be used in any of the five boroughs, at any hour. A separately issued adult Class D license has different privileges."
            case .longIsland:
                night = "Supervised; narrow solo exceptions"
                nightDetail = "In Nassau and Suffolk, junior drivers generally need an approved supervisor. Solo travel is limited to specific work, school or farm trips; the 9 PM–5 AM exceptions are narrower. See the DMV list."
                supervision = "Approved supervisor, age 21+"
            case .upstate: break
            case nil:
                night = "Choose a New York region"
                passengers = "Rules depend on driving region"
                supervision = "Regional rules apply"
            }
        }

        if stage == .permit {
            night = "Supervised driving only"
            nightDetail = guide.permitConditions
            passengers = "Permit passenger rules"
            passengerDetail = guide.permitConditions
            supervision = "A supervising driver is required"
            supervisionDetail = guide.permitSupervisor
            other = guide.permitConditions
            switch guide.id {
            case "FL": night = beforeMonths(3) == false ? "Supervised, until 10 PM" : "First 3 months: daylight only"
            case "DC": night = "Supervised, 6 AM–9 PM"
            case "HI": night = "11 PM–5 AM: parent/guardian"
            case "SC": night = "Midnight–6 AM: qualified supervisor"
            case "TN": night = "Under 18: supervised, 6 AM–10 PM"
            case "NC": night = beforeMonths(6) == false ? "Supervised, any time" : "First 6 months: 5 AM–9 PM"
            case "IL": night = "Under 18: 10 / 11 PM–6 AM restricted"
            case "MA": night = "Midnight–5 AM: parent/guardian"
            case "KY": night = "Under 18: midnight–6 AM restricted"; passengers = "1 unrelated passenger under 20"
            case "WV": night = "Supervised, 5 AM–10 PM"; passengers = "2 nonfamily + supervising adult"
            case "NJ": night = "Under 21: 11:01 PM–5 AM restricted"; passengers = "Dependents + parents/guardians + 1"
            case "VA": passengers = "1 passenger under 18, excluding family"
            case "CT": passengers = "Approved supervisors/parents only"
            case "DE": passengers = "Supervisor + 1; family exception applies"
            default: break
            }
            if guide.id == "NH" { supervision = "Supervised learning, no permit issued" }
            if guide.id == "NY", age.map({ $0 < 18 }) != false {
                night = preferences.newYorkRegion == .upstate ? "9 PM–5 AM: approved supervisor" : "5 AM–9 PM only"
                if preferences.newYorkRegion == nil { night = "Choose a New York region" }
            }
        } else if !teenLicense || !isTeen {
            night = "Check your license conditions"
            passengers = "Check your license conditions"
            nightDetail = "Full-license selection does not remove restrictions from your credential. Age-based rules, local curfews and any printed limits still apply."
            passengerDetail = "Use the official guide to confirm your credential is unrestricted. Seat-belt and child-restraint laws still apply."
            supervision = "Follow your issued credential"
            supervisionDetail = "Roam does not upgrade a permit or license when a time period or birthday is reached."
            // Device rules can apply by age or credential independently of GDL hours.
            other = guide.other
        }

        if guide.id == "NY", let age, age < 16 {
            night = "Under 16: no driving in New York"
            passengers = "Driving is not permitted"
            supervision = "An adult does not waive the age rule"
            nightDetail = "New York does not permit driving under 16, including on an out-of-state permit or license."
        }

        let ageText = age.map { "Age \($0)" } ?? "Age not added"
        let phaseText = issue.map { "Issued \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Issue date not added"
        return DrivingRestrictionSummary(guide: guide, rules: [
            .init(kind: .hours, summary: night, detail: nightDetail),
            .init(kind: .passengers, summary: passengers, detail: passengerDetail),
            .init(kind: .supervision, summary: supervision, detail: supervisionDetail),
            .init(kind: .other, summary: "Phones, documents & conditions", detail: other)
        ], context: "\(ageText) · \(phaseText)", needsAge: age == nil,
           needsIssueDate: issue == nil, needsRegion: needsRegion,
           needsSourceRefresh: now.timeIntervalSince(sourceReviewDate) > 180 * 86_400)
    }
}
