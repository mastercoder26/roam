# README media

The main README uses authentic app captures, a small charcoal frame, and the
existing Roam wordmark and two app-icon variants. The framing adds no gradients,
shadows, or replacement UI.

## Screenshot sources

Captured October 26, 2026 from the current SwiftUI app on an iPhone simulator.
Every original in `raw/` is 1206 by 2622 pixels, with the status bar set to
9:41 and a full battery. All screenshots use dark appearance. Originals remain
available through the gallery links.

| File | Screen and state |
| :--- | :--- |
| `routes.png` | Routes, dark appearance, before entering a route. |
| `route-score.png` | Route details, dark appearance, built-in sample result. |
| `drive.png` | Active Drive screen, dark appearance, showing a simulated 28 mph GPS reading. Extracted from the recorded walkthrough. |
| `progress.png` | Progress, dark appearance, clean first-use state. |
| `profile.png` | Profile, dark appearance, signed out. |
| `route-breakdown.png` | Route breakdown, dark appearance, with all three demand explanations expanded. Uses the built-in sample result. |

The route score was exported from the existing route details UI test's
screenshot attachments. The expanded breakdown was captured during the new
walkthrough. Other captures used the app's debug preview launch arguments.
The sample result illustrates the interface; its values are not a measured
drive or a real-time route analysis.

## Rebuild the frames

After installing the web app's existing dependencies, run from the repo root:

```bash
node docs/assets/readme/render-assets.mjs
```

This resizes each original proportionally and adds rounded corners and a flat
frame. It writes the gallery PNGs beside this file. It also exports the existing
primary and alternate app-icon previews as 144-pixel PNGs for the header.
It does not change the original screenshots or invent UI content.

## Recorded walkthrough

`roam-walkthrough.mp4` is a new recording of the native app being operated in
dark mode. A recorder harness in a temporary app copy rehearsed the flow before
recording it with `simctl io recordVideo`. The application source in this
repository was not modified to produce the recording.

The walkthrough includes the route score, all three expanded demand
explanations, weather and road details, the experience comparison, a profile
pull gesture, editing the demo name Avery, Progress, and manual recording
controls with pause, resume, lock, and unlock interactions.

Route analysis uses the app's built-in sample result. The drive-control segment
uses explicitly simulated GPS movement in Stockton, California. It demonstrates
the controls and does not represent a real drive or validated coaching score.
The caption alongside the phone identifies the simulator and sample data.

Launch screens and long automation waits were trimmed. Some clips use modest
speed adjustments for pacing. The delivery is a silent, captioned H.264 MP4
with a flat background and no added gradients. The app screen itself remains
the native recording.

`walkthrough-preview.gif` is a short excerpt from the delivered video, showing
the route explanations opening. It links to the complete MP4 in the README.

```bash
ffmpeg -ss 11.7 -t 7 -i docs/assets/readme/roam-walkthrough.mp4 \
  -filter_complex '[0:v]fps=10,scale=840:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=1,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a' \
  -loop 0 docs/assets/readme/walkthrough-preview.gif
```
