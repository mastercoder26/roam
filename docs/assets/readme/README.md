# README media

The main README uses authentic app captures, a small charcoal frame, and the
existing Roam wordmark from `web/public/brand/roam-wordmark.png`. The framing
adds no gradients, shadows, or replacement UI.

## Screenshot sources

Captured October 26, 2026 from the current SwiftUI app on an iPhone simulator.
Every original in `raw/` is 1206 by 2622 pixels, with the status bar set to
9:41 and a full battery. All screenshots use dark appearance. Originals remain
available through the gallery links.

| File | Screen and state |
| :--- | :--- |
| `routes.png` | Routes, dark appearance, before entering a route. |
| `route-score.png` | Route details, dark appearance, built-in sample result. |
| `drive.png` | Drive, dark appearance, clean first-use state. |
| `progress.png` | Progress, dark appearance, clean first-use state. |
| `profile.png` | Profile, dark appearance, signed out. |
| `route-breakdown.png` | Route breakdown, dark appearance, built-in sample result. |

The route score and breakdown were exported from the existing route details UI
test's screenshot attachments. Other captures used the app's debug preview
launch arguments. The sample result illustrates the interface; its values are
not a measured drive or a real-time route analysis.

## Rebuild the frames

After installing the web app's existing dependencies, run from the repo root:

```bash
node docs/assets/readme/render-assets.mjs
```

This resizes each original proportionally and adds rounded corners and a flat
frame. It writes the gallery PNGs beside this file. It does not change the
original screenshots or invent UI content.

## Interaction loop

`profile-interaction.gif` is a reduced-size conversion of the existing
`docs/assets/profile-pull-down.mp4`, with a one-second hold at the end.

```bash
ffmpeg -i docs/assets/profile-pull-down.mp4 \
  -filter_complex '[0:v]fps=12,scale=360:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=1,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a' \
  -loop 0 docs/assets/readme/profile-interaction.gif
```
