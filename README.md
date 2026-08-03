# Roam

Roam helps families plan for a drive and practise safer driving. The iOS app
has four tabs:

- **Routes** scores a planned route's driving difficulty, compares returned
  choices with private recorded experience, offers guided practice plans, and
  compares nearby departure times when the underlying conditions are
  available.
- **Drive** is a manually started, on-device driving session that combines GPS
  speed changes and phone motion to flag hard braking, rapid acceleration,
  sharp corners, and abrupt phone movement. While a drive is active, its
  elapsed time and measured stats are available in a Live Activity on the Lock
  Screen and Dynamic Island.
- **Progress** shows an evidence-weighted, route-adjusted coaching score plus
  measured local evidence such as validated miles, after-dark miles, 45+ mph
  miles, continuous-trace coverage, and an eight-week chart.
- **Profile** shows the driver's name, licensing stage, and lifetime record
  derived from locally recorded drives, plus the app's appearance controls. It
  introduces no network calls and stores only the display name and licensing
  stage, both user-declared and excluded from every score.

This is a prototype, not a safety system or an emergency service. A drive score
is coaching feedback, not a guarantee that a person or route is safe.

## How scoring uses data

Route difficulty is a **driver task-demand estimate**, not a crash-risk
prediction or a guarantee of safety. It combines Google Routes geometry,
maneuvers, traffic-aware ETA, and best-effort live enrichment from Open-Meteo
and OpenStreetMap/Overpass.
Posted speed limits are assigned only to the matching sampled portion of a
route; when that coverage is unavailable, Roam falls back to per-step route
timing instead of applying a route-wide average. After-dark exposure uses the
route location, travel date, and local departure time to estimate sunrise and
sunset (with a conservative clock-time fallback when those inputs are
unavailable). Every OSM road field is ignored unless its lookup succeeded. The
app lists the live sources that contributed to each result and shows an
uncertainty band.

Manual driving scores are local to the device. Roam rejects poor GPS fixes,
derives braking and acceleration from changes in accepted GPS speed, uses
course change for sharp-corner signals, and transforms gravity-free Core Motion
readings into a vertical reference frame. Possible phone handling requires a
sustained acceleration-and-rotation pattern while fresh GPS shows the vehicle
is moving; a single bump or parked-phone movement is ignored. Scores are
normalized to distance; short or sparse drives are labelled **Preliminary**
instead of being presented as precise assessments.

When a route is queued or active for practice, its address and planned polyline
stay in memory only. The saved planned-route context retains only stable demand
IDs, numeric coverage, goal status, and local timestamps. The local drive
record separately retains its GPS trace and coaching events for private replay.
After a completed drive with a continuous trace, Roam automatically sends
only its measured start and end coordinates to the configured route-analysis
service to calculate route difficulty. It stores the resulting compact
difficulty snapshot locally, never the sent endpoint text or returned route
geometry. Analysis uses conditions available after the drive ends, so it does
not reconstruct historical traffic or weather. A failed analysis never removes
the drive or its local coaching score. A post-drive debrief distinguishes
verified practice, partial coverage, missing GPS coverage, and a drive that
remains preliminary.

The first minute of a manual drive can show a non-blocking sensor-placement
advisory only after fresh GPS shows the car moving and the existing
high-confidence motion detector sees two separate episodes. It never identifies
handheld use and stores only the final advisory status, not raw motion samples.

## Run the iOS app

Open [Roam.xcodeproj](ios/Roam.xcodeproj) in Xcode, choose an iPhone
simulator or physical iPhone, and press Run. The Drive tab needs a physical
iPhone for meaningful accelerometer and location readings; the Simulator is
useful for UI only.

On first manual drive, iOS asks for location and motion permissions. Roam
uses them only while the user has explicitly started a drive. Recorded drives,
route overlap, replay moments, readiness comparisons, and progress totals are
stored locally on the device. No account or cloud sync is part of this
prototype. Automatic post-drive difficulty analysis sends only the drive's
start and destination coordinates to the configured route-analysis service;
the full recorded history and GPS trace are not uploaded.

For a physical iPhone, copy `ios/Roam/Config/Debug.local.example.xcconfig`
to `Debug.local.xcconfig` and replace `YOUR_MAC_LAN_IP` with your Mac’s current
Wi-Fi IP. The local file is ignored by Git; do not put a private network address
in the shared project configuration.

For a manual drive that continues while the phone is locked, iOS may also ask
for **Always Allow** location access after the drive begins. It enables location
updates only for the active session and turns them off when the user ends it.

## Live Activity and CarPlay

Roam starts a Live Activity only after the driver manually starts a drive. It
shows elapsed time, measured speed, distance, and event count. It contains no
route, address, or raw location data and ends when the drive ends.

The project also includes a CarPlay information dashboard for an active drive.
It mirrors elapsed time, distance, speed, current motion, and measured events;
starting and ending drives remain iPhone-only. To appear on a real CarPlay head
unit, the app's Apple Developer identifier and provisioning profile must be
approved for the relevant CarPlay category, normally the Maps entitlement for a
driving app. This Apple-controlled entitlement is intentionally not enabled in
the repository, so adding the project to an iPhone will not fail for developers
who have not received it.

## Run the backend

The iOS app uses the API in `backend/`. From the repository root:

```bash
npm run dev
```

This delegates to `backend/npm run dev` and starts the API at
`http://localhost:3000`. Ensure `backend/.env.local` contains the required
Google Maps API key.

If port 3000 is already in use, either stop the existing development server
with `Ctrl+C` in its terminal, or use another port:

```bash
PORT=3001 npm run dev
```

Run the backend scoring tests with:

```bash
npm test
```

Run the deterministic manual-drive checks with:

```bash
swiftc ios/Roam/Models/RouteDifficultyModels.swift ios/Roam/Models/PhonePlacementAnalyzer.swift ios/Roam/Models/DriveScoringEngine.swift ios/Roam/Models/DrivingScore.swift ios/Roam/Models/DriveExperienceEngine.swift ios/Roam/Models/DriverReadinessModels.swift ios/Roam/Models/DriverReadinessSupport.swift ios/Roam/Models/DriverReadinessConfiguration.swift ios/Roam/Models/DriverReadinessProfileBuilder.swift ios/Roam/Models/DriverReadinessRouteMatcher.swift ios/Roam/Models/DriverReadinessEngine.swift ios/Roam/Models/PracticePlanEngine.swift ios/Roam/Models/DriverPerformanceEngine.swift ios/tests/DriveScoringEngineChecks.swift -o /tmp/roam-drive-checks
/tmp/roam-drive-checks
```

Run the overall driver-performance checks with:

```bash
swiftc ios/Roam/Models/RouteDifficultyModels.swift ios/Roam/Models/PhonePlacementAnalyzer.swift ios/Roam/Models/DriveScoringEngine.swift ios/Roam/Models/DrivingScore.swift ios/Roam/Models/DriveExperienceEngine.swift ios/Roam/Models/DriverReadinessModels.swift ios/Roam/Models/DriverReadinessSupport.swift ios/Roam/Models/DriverReadinessConfiguration.swift ios/Roam/Models/DriverReadinessProfileBuilder.swift ios/Roam/Models/DriverReadinessRouteMatcher.swift ios/Roam/Models/DriverReadinessEngine.swift ios/Roam/Models/PracticePlanEngine.swift ios/Roam/Models/DriverPerformanceEngine.swift ios/tests/DriverPerformanceEngineChecks.swift -o /tmp/roam-performance-checks
/tmp/roam-performance-checks
```

Run the drive-history policy checks with:

```bash
swiftc ios/Roam/Models/DriveHistoryPolicy.swift ios/tests/DriveHistoryPolicyChecks.swift -o /tmp/roam-history-checks
/tmp/roam-history-checks
```

Run the theme catalog checks with:

```bash
swiftc ios/Roam/Models/Theme.swift ios/tests/ThemeCatalogChecks.swift -o /tmp/roam-theme-checks
/tmp/roam-theme-checks
```

Run the route-entry state checks with:

```bash
swiftc ios/Roam/Models/RoutePlanningLocationCoordinator.swift ios/tests/RoutePlanningLocationChecks.swift -o /tmp/roam-route-location-checks
/tmp/roam-route-location-checks
```

Run the launch intro choreography checks with:

```bash
swiftc ios/Roam/Models/LaunchIntroChoreography.swift ios/tests/LaunchIntroChoreographyChecks.swift -o /tmp/roam-intro-checks
/tmp/roam-intro-checks
```

The route-readiness, practice, replay, placement, progress, departure-time,
shared-route-import, and layout/presentation checks are standalone Swift
command-line checks in `ios/tests/`. They cover the private local engines
separately from the iOS app target.

## Open source and attribution

Roam is available under the [MIT License](LICENSE).

The manual-drive feature is an original implementation built with Apple
CoreLocation and CoreMotion. Its scope and product direction were informed by
[DriveSense](https://github.com/wuisabel-gif/Drive-Sense), an MIT-licensed
open-source project. No DriveSense source code is included in this repository.
If DriveSense code is incorporated in a future change, its MIT copyright and
license notice will be retained with that copied code.

## Privacy and safety

- Do not operate the app while driving. Start a session before leaving and end
  it only after safely parking.
- The **Get help** control explains that Roam cannot detect crashes or call
  for help automatically; it can open the phone’s emergency-call flow only
  when the user explicitly taps it.
- Never commit API keys. Put local backend keys in `backend/.env.local`.
