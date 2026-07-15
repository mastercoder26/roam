# Swerve

Swerve helps families plan for a drive and practise safer driving. The iOS app
has two focused modes:

- **Routes** scores a planned route’s driving difficulty and explains why.
- **Drive** is a manually started, on-device driving session that combines GPS
  speed changes and phone motion to flag hard braking, rapid acceleration,
  sharp corners, and abrupt phone movement.

This is a prototype, not a safety system or an emergency service. A drive score
is coaching feedback, not a guarantee that a person or route is safe.

## How scoring uses data

Route difficulty combines Google Routes geometry, maneuvers, traffic-aware ETA,
and best-effort live enrichment from Open-Meteo and OpenStreetMap/Overpass.
Posted speed limits are assigned only to the matching sampled portion of a
route; when that coverage is unavailable, Swerve falls back to per-step route
timing instead of applying a route-wide average. The app lists the live sources
that contributed to each result and shows an uncertainty band.

Manual driving scores are local to the device. Swerve rejects poor GPS fixes,
derives braking and acceleration from changes in accepted GPS speed, uses
course change for sharp-corner signals, and transforms gravity-free Core Motion
readings into a vertical reference frame to corroborate motion. Scores are
normalized to distance; short or sparse drives are labelled **Preliminary**
instead of being presented as precise assessments.

## Run the iOS app

Open [Swerve.xcodeproj](ios/Swerve.xcodeproj) in Xcode, choose an iPhone
simulator or physical iPhone, and press Run. The Drive tab needs a physical
iPhone for meaningful accelerometer and location readings; the Simulator is
useful for UI only.

On first manual drive, iOS asks for location and motion permissions. Swerve
uses them only while the user has explicitly started a drive. The current
prototype keeps the resulting score in memory on the device.

For a physical iPhone, copy `ios/Swerve/Config/Debug.local.example.xcconfig`
to `Debug.local.xcconfig` and replace `YOUR_MAC_LAN_IP` with your Mac’s current
Wi-Fi IP. The local file is ignored by Git; do not put a private network address
in the shared project configuration.

For a manual drive that continues while the phone is locked, iOS may also ask
for **Always Allow** location access after the drive begins. It enables location
updates only for the active session and turns them off when the user ends it.

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
swiftc ios/Swerve/Models/DrivingScore.swift ios/Swerve/Models/DriveScoringEngine.swift ios/tests/DriveScoringEngineChecks.swift -o /tmp/swerve-drive-checks
/tmp/swerve-drive-checks
```

Run the route-entry state checks with:

```bash
swiftc ios/Swerve/Models/RoutePlanningLocationCoordinator.swift ios/tests/RoutePlanningLocationChecks.swift -o /tmp/swerve-route-location-checks
/tmp/swerve-route-location-checks
```

## Open source and attribution

Swerve is available under the [MIT License](LICENSE).

The manual-drive feature is an original implementation built with Apple
CoreLocation and CoreMotion. Its scope and product direction were informed by
[DriveSense](https://github.com/wuisabel-gif/Drive-Sense), an MIT-licensed
open-source project. No DriveSense source code is included in this repository.
If DriveSense code is incorporated in a future change, its MIT copyright and
license notice will be retained with that copied code.

## Privacy and safety

- Do not operate the app while driving. Start a session before leaving and end
  it only after safely parking.
- The **Get help** control explains that Swerve cannot detect crashes or call
  for help automatically; it can open the phone’s emergency-call flow only
  when the user explicitly taps it.
- Never commit API keys. Put local backend keys in `backend/.env.local`.
