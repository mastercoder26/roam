# Intro Render Tooling

This directory contains the headless rendering pipeline for generating Roam theme visual assets and launch intros using Puppeteer and Three.js.

## Directory Structure

- `intro-render/`: Headless Puppeteer + Three.js rendering pipeline.
  - `capture.mjs`: Automation script rendering the themes using ANGLE/Metal GPU acceleration.
  - `themes.mjs`: Visual themes definition matching Roam's color palette.
  - `public/`: Three.js scene assets, shader configurations, and HTML templates.
  - `out/`: Temporary render output directory (ignored by git).
