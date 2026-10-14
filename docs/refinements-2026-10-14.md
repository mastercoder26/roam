# Roam refinements, October 14, 2026

Roam helps new drivers plan a route, record practice, and understand their progress. This pass makes those tasks easier to scan and fixes cases where missing data, invalid sensor readings, or delayed work produced misleading results.

## Interface

- Route results keep the score, readiness gaps, and supervision guidance visible. Practice instructions, history facts, and supporting comparisons expand on demand.
- Recent routes lead with the destination and group the difficulty label with its score.
- The help sheet opens with three short steps. Detailed scoring, recording, and confidence explanations are expandable.
- Route checks use a route icon and direct labels. The walkthrough names the tabs without lengthy explanations.
- The walkthrough uses four user-supplied oil paintings bundled in the asset catalog. Rounded artwork cards carry white titles and short descriptions over a dark gradient. Next stays below the card, and the story scrolls when larger text needs more room.
- Walkthrough pages slide and fade together with a small incoming scale change. Reduced Motion uses a brief crossfade. Each outgoing page retains its own painting and text, while the controls stay fixed.
- Paintings are stored as 1536 × 1024 JPEGs in `ios/Roam/Assets.xcassets/Walkthrough{Plan,Understand,Drive,Grow}.imageset`, about 3.8 MiB combined. The compiled asset catalog contains all four, so the walkthrough requires no network download.
- The web map has one grouped summary panel, fewer repeated reasons, and less technical copy. Invalid baseline duration no longer appears as a zero-minute typical drive.
- Removed the web backend/model-version footer and the live score's em-dash placeholder. The measuring state uses an ellipsis.
- Web privacy copy distinguishes on-device scoring and route traces from account backup of drive summaries.

## Motion and navigation

- The launch logo uses measured header coordinates, including cold launches before the main view mounts.
- The launch screen uses the app's default dark appearance, avoiding a bright flash before the intro. Existing SwiftUI theme selection still supplies the app's chosen color scheme.
- Loading handles a result that arrives immediately, allows the car to finish assembling, and cancels delayed callbacks when removed.
- Reduced Motion avoids the car's slide, dot movement, intro scaling, and root-header slide.
- Route requests capture their input values once, cancel when a new shared route arrives or the form disappears, and ignore canceled responses.
- Repeated taps cannot start duplicate checks. Successful handoff and failures release the task so another route can be checked.

## Scoring

- Missing or invalid normal travel duration no longer makes the entire trip appear to be traffic delay.
- Solar calculations correctly handle UTC+13 departures rather than using an inappropriate fixed nighttime cutoff.
- Reject non-finite GPS speed, invalid course angles, unavailable course accuracy, and invalid motion samples.
- Avoid integer overflow in location-sample confidence calculations.
- Invalid drive or trace durations cannot earn high confidence after normalization.
- Live smoothness ignores future readings. Clean streaks use the latest event that actually occurred, even if events arrive out of order.
- Invalid route difficulty cannot qualify for performance scoring. Non-finite durations cannot qualify a drive for saving.

## Validation

- Backend: all 165 tests pass; TypeScript build passes.
- Web: production build and final TypeScript check pass.
- iOS: all 29 standalone Swift checks pass after focused reruns. Two initial compilations overlapped source edits; the walkthrough check caught missing tab names, which were restored. The shared-route inbox check requires macOS file-coordination access and passes outside the filesystem sandbox.
- Signed iOS simulator build passes. Captured and inspected the launch sequence and initial route screen on iPhone 18 Pro.
- Rebuilt and installed the painted walkthrough. Inspected all four rounded cards, image crops, text overlays, progress updates, and the completion action on iPhone 18 Pro. Motion code uses captured page content, ordered transition layers, and an unanimated scroll reset.
- Property-list validation and `git diff --check` pass.

An unlocked-device pass verified the help disclosures, tab navigation, empty Progress action, Preferences, Light and Dark theme selection, and walkthrough completion. Larger text sizes and authenticated result screens still need interactive verification. Real driving and sensor behavior were tested through engine regressions, not an on-road recording.

## Design references

- [Grab Driver score report](https://mobbin.com/screens/5152c40b-c0ec-460f-9a4d-0ed9134099a2): a prominent score, brief coaching, and secondary details.
- [Mercedes-Benz trip data](https://mobbin.com/screens/9885fc6e-2b3d-4e30-b5a2-aed13899728f): grouped, concise label/value rows.
- [Apple's app appearance setting](https://developer.apple.com/documentation/bundleresources/information-property-list/uiuserinterfacestyle): default appearance during launch.

Four GPT 6.1 Sol subagents covered scoring, motion, and native design; GPT 6 Luna handled the lighter web pass because GPT 6.1 Luna was unavailable. Existing local work was preserved. No commits, pushes, or deployments were made.
