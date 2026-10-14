# Roam — A little more confidence

`Roam-Promo.mp4` is the finished 24-second landscape promo, 1920 × 1080 at 60 fps, with a stereo AAC mix. `Roam.tsrct` is the portable editable Tesseract 0.3.1 project. Open `Preview.html` for a simple local video player.

The miniature car, tires, windows, road, trees, platform and progress pillars are solid procedural 3D geometry rendered by native WGSL effects in Tesseract. Text, logo, UI, transition wipes and sound layers remain independently editable. This project uses no generated footage, fabricated app metrics, narration or commercial music samples.

The route-planning image is a faithful crop of the existing `ad/assets/app-route.png`, retaining the app's actual heading and route form. The crop excludes the status bar, map and error banner. Product claims are grounded in the repository README. The supplied blue Roam wordmark is used unchanged.

## Edit and soundtrack

| Time | Picture | Audio |
|---|---|---|
| 0–4 s | Rotating toy car; “New driver. Big world.” | Electric keys, bass and swung drums; light opening accent |
| 4–10 s | Real route-planning UI over a miniature road | Melody enters; one restrained transition accent |
| 10–14 s | Car on a curved practice road with growing trees | Groove continues |
| 14–18 s | Three dimensional pillars rise to represent progress | Soft staggered pops follow the growth |
| 18–24 s | Large supplied wordmark and “Build confidence. Go roam.” | Resolving C-major chord at 22 s and natural release |

The original instrumental was locally composed at 120 BPM. Separate keys/bass and percussion stems, synthesis recipe, motion accents, source timing and music waveform are retained under `.tesseract-work`. Music is mixed as native Audio layers; final mastering is recorded in `.tesseract-work/checks/mastering.json` and reproducible with `master.py`.

## Review

- Inspected the actual opening and two native filmstrips, including entrances, holds, every scene handoff and the ending. Corrected the road being occluded by its platform, bounded its dash pattern, and added directional wipes that cover the model scale changes.
- Final browser playback was checked using the actual MP4. It loaded at 1920 × 1080, advanced through the edit, and reached the end without a media error.
- FFprobe confirms 24.000 seconds, H.264 video at 60 fps, and stereo 48 kHz AAC audio.
- Measured final mix: −15.06 LUFS integrated, −1.50 dBTP true peak, 2.6 LU loudness range. A separate mono band-limited diagnostic copy is retained.
- The music waveform was inspected and cues follow the authored beat grid. This environment did not provide audible monitoring to the agent, so subjective listening, musical feel and phone-speaker audition remain unverified. Meter and waveform checks do not substitute for listening.

`Previews/Poster.png` and `Previews/Filmstrip-v2.png` correspond to the delivered visual revision. All rendering was performed locally by Tesseract. Final mastering changes only audio; video was stream-copied from the native export. No publishing or remote upload was performed.

The embedded Avenir Next collection is a local macOS system font. Keep this project local unless its font redistribution terms permit the intended sharing.
