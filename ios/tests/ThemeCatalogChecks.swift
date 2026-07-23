import Foundation

@main
struct ThemeCatalogChecks {
    static func main() {
        expect(ThemeCatalog.default == .dark, "default theme should remain dark")
        expect(ThemeID.allCases.count == 6, "expected six curated themes")

        expect(
            ThemeCatalog.resolve(rawValue: nil) == .dark,
            "missing persistence should fall back to dark"
        )
        expect(
            ThemeCatalog.resolve(rawValue: "not-a-theme") == .dark,
            "unknown persistence should fall back to dark"
        )
        expect(
            ThemeCatalog.resolve(rawValue: ThemeID.goldfish.rawValue) == .goldfish,
            "goldfish should round-trip from storage"
        )

        let dark = ThemeCatalog.palette(for: .dark)
        expect(dark.appearance == .dark, "dark theme uses dark appearance")
        expect(nearlyEqual(dark.accent.red, 0.02), "dark accent red channel")
        expect(nearlyEqual(dark.accent.green, 0.42), "dark accent green channel")
        expect(nearlyEqual(dark.accent.blue, 0.92), "dark accent blue channel")

        let light = ThemeCatalog.palette(for: .light)
        expect(light.appearance == .light, "light theme uses light appearance")
        expect(light.canvas.red > 0.9, "light canvas should be bright")
        expect(light.inkPrimary.red < 0.2, "light ink should be dark")

        let goldfish = ThemeCatalog.palette(for: .goldfish)
        expect(goldfish.appearance == .light, "goldfish is a light warm scheme")
        expect(goldfish.accent.red > 0.9, "goldfish accent should skew warm/red")
        expect(goldfish.accent.green > 0.3 && goldfish.accent.green < 0.6, "goldfish accent green")
        expect(goldfish.canvas.red > 0.95, "goldfish canvas should feel creamy")

        for id in ThemeID.allCases {
            let palette = ThemeCatalog.palette(for: id)
            expect(!id.title.isEmpty, "\(id.rawValue) needs a title")
            expect(!id.subtitle.isEmpty, "\(id.rawValue) needs a subtitle")
            expect(palette.accent.alpha > 0, "\(id.rawValue) accent must be visible")
            expect(palette.canvas.alpha > 0, "\(id.rawValue) canvas must be opaque")
        }

        print("ThemeCatalog checks passed")
    }

    private static func nearlyEqual(_ value: Double, _ expected: Double, tolerance: Double = 0.001) -> Bool {
        abs(value - expected) <= tolerance
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError("ThemeCatalog check failed: \(message)")
        }
    }
}
