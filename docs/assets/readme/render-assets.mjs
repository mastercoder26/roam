import { createRequire } from 'node:module';
import { readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Use the image library already installed by the web app. No extra dependencies.
const require = createRequire(import.meta.url);
const sharp = require('../../../web/node_modules/sharp');
const directory = dirname(fileURLToPath(import.meta.url));
const width = 600;
const bezel = 8;

for (const file of (await readdir(join(directory, 'raw'))).sort()) {
  if (!file.endsWith('.png')) continue;
  const input = join(directory, 'raw', file);
  const metadata = await sharp(input).metadata();
  const height = Math.round(metadata.height * width / metadata.width);
  const radius = Math.round(width * 0.095);
  const mask = Buffer.from(`<svg width="${width}" height="${height}">
    <rect width="${width}" height="${height}" rx="${radius}" fill="white"/>
  </svg>`);
  const screen = await sharp(input)
    .resize({ width })
    .composite([{ input: mask, blend: 'dest-in' }])
    .png()
    .toBuffer();
  const frameWidth = width + bezel * 2;
  const frameHeight = height + bezel * 2;
  const frame = Buffer.from(`<svg width="${frameWidth}" height="${frameHeight}">
    <rect x="1" y="1" width="${frameWidth - 2}" height="${frameHeight - 2}"
      rx="${radius + bezel}" fill="#1a1b20" stroke="#46474b" stroke-width="2"/>
  </svg>`);
  await sharp(frame)
    .composite([{ input: screen, left: bezel, top: bezel }])
    .png({ compressionLevel: 9, palette: true, colours: 256, dither: 0.5 })
    .toFile(join(directory, file));
  console.log(`Framed ${file}: ${frameWidth} × ${frameHeight}`);
}

for (const [source, output] of [
  ['AppIconPrimaryPreview', 'roam-app-icon.png'],
  ['AppIconWordmarkPreview', 'roam-alternate-icon.png'],
]) {
  await sharp(join(directory, '../../../ios/Roam/Assets.xcassets', `${source}.imageset`, `${source}.png`))
    .resize(144, 144)
    .png()
    .toFile(join(directory, output));
}
