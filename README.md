# Swerve

Swerve helps families plan for a drive and practise safer driving. The iOS app
has two focused modes:

- **Routes** scores a planned route’s driving difficulty and explains why.
- **Drive** is a manually started, on-device driving session that combines GPS
  speed changes and phone motion to flag hard braking, rapid acceleration,
  sharp corners, and abrupt phone movement.

This is a prototype, not a safety system or an emergency service. A drive score
is coaching feedback, not a guarantee that a person or route is safe.

## Run the iOS app

Open [Swerve.xcodeproj](ios/Swerve.xcodeproj) in Xcode, choose an iPhone
simulator or physical iPhone, and press Run. The Drive tab needs a physical
iPhone for meaningful accelerometer and location readings; the Simulator is
useful for UI only.

On first manual drive, iOS asks for location and motion permissions. Swerve
uses them only while the user has explicitly started a drive. The current
prototype keeps the resulting score in memory on the device.

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
