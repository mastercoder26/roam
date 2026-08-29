import Foundation

@main
struct ProductionConfigurationChecks {
    static func main() throws {
        let iosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = iosDirectory
            .appendingPathComponent("Roam")
            .appendingPathComponent("PrivacyInfo.xcprivacy")
        let projectURL = iosDirectory
            .appendingPathComponent("Roam.xcodeproj")
            .appendingPathComponent("project.pbxproj")

        expect(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "the main app target must contain PrivacyInfo.xcprivacy"
        )

        let data = try Data(contentsOf: manifestURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let manifest = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any] else {
            fail("PrivacyInfo.xcprivacy must be a property-list dictionary")
        }

        expect(
            manifest["NSPrivacyTracking"] as? Bool == false,
            "the app must explicitly declare that it does not track users"
        )
        expect(
            (manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true,
            "an app that does not track users must not list tracking domains"
        )

        let accessedAPIs = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let userDefaultsReasons = accessedAPIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }?["NSPrivacyAccessedAPITypeReasons"] as? [String]
        expect(
            userDefaultsReasons?.contains("CA92.1") == true,
            "the manifest must declare the app-only UserDefaults required reason"
        )

        let collectedData = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let collectedTypes = Set(collectedData.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        let requiredCollectedTypes: Set<String> = [
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeOtherUsageData"
        ]
        expect(
            requiredCollectedTypes.isSubset(of: collectedTypes),
            "the manifest must describe the account and aggregate driving data stored by Roam"
        )
        for entry in collectedData where requiredCollectedTypes.contains(entry["NSPrivacyCollectedDataType"] as? String ?? "") {
            expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, "account data is linked to the signed-in user")
            expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "Roam does not use account data for tracking")
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
            expect(
                purposes.contains("NSPrivacyCollectedDataTypePurposeAppFunctionality"),
                "each collected account data type must declare its app-functionality purpose"
            )
        }

        let project = try String(contentsOf: projectURL, encoding: .utf8)
        expect(
            project.contains("PrivacyInfo.xcprivacy in Resources"),
            "the privacy manifest must be copied into the main app bundle"
        )

        print("Production configuration checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError("Production configuration check failed: \(message)")
    }
}
