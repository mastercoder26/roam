# Swerve iOS app

Native SwiftUI frontend for the Drive Difficulty backend.

## Run it in Simulator

1. Start the API from the repository root: `npm run dev --prefix backend`.
2. Open `ios/Swerve.xcodeproj` in Xcode.
3. Choose an iPhone Simulator and press Run.
4. The default backend is `http://127.0.0.1:3000`. Change it through the gear button if needed.

The app permits HTTP solely so the local development backend works. Use HTTPS before any production distribution.

## Product roadmap

The current UI implements route difficulty and its explanation. Swift supports the next product layers:

- Core Motion for acceleration/braking/turning telemetry (with explicit consent)
- Core ML / Vision for on-device models and camera-based wildlife detection
- MapKit, notification, and background-task APIs for trip guidance, subject to iOS safety and background-execution limits
- a server-side data pipeline for model training, evaluation, and versioning

Do not claim the scoring model is a neural network or trained on real driver data until that pipeline, its evaluation, and supporting evidence exist.
