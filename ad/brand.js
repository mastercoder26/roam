'use strict';
// Roam brand values, taken from web/tailwind.config.ts and the app icon.
const ROAM = {
  blue: '#3158D4', navy: '#1a2340', ink: '#18203b', canvas: '#F4F5F2', paper: '#f4f3ee', grey: '#5F656B', grey2: '#8A9095',
  green: '#55A766', deep: '#198A62', amber: '#D49A16', orange: '#E77B12', red: '#D44C42', safety: '#C76A20',
  sky: '#cfe0f7', road: '#c9cdcc', grass: '#bcd9a4',
};
const UI_FONT = '-apple-system, "SF Pro Display", "Helvetica Neue", Helvetica, Arial, sans-serif';

const ROAM_PALETTE = makePalette({
  paper: ROAM.paper, ink: ROAM.ink, night: ROAM.navy, chalk: '#f4f3ee', chalkDim: '#9aa3c7',
  fills: [ROAM.blue, ROAM.green, ROAM.amber, ROAM.orange, ROAM.red, ROAM.deep], shade: ROAM.ink, light: '#ffffff', blush: ROAM.orange,
  accents: [ROAM.blue, ROAM.amber, ROAM.green, ROAM.red], inks: [ROAM.ink, ROAM.blue], finish: 'flat', washBlend: 'multiply',
}, 'doodlePastel');

// App-style type: the product's own system font, placed on the hand-drawn page.
function uiText(c, str, x, y, o = {}) {
  const { size = 40, weight = 700, color = ROAM.ink, align = 'left', track = 0, al = 1, base = 'alphabetic' } = o;
  if (al <= 0) return;
  c.save(); c.globalAlpha *= clamp(al, 0, 1); c.fillStyle = color; c.font = `${weight} ${size}px ${UI_FONT}`;
  c.textAlign = align; c.textBaseline = base; c.letterSpacing = `${track}px`; c.fillText(str, x, y); c.restore();
}
// A line of type that rises into place as it fades in.
function riseText(c, str, x, y, k, o = {}) { if (k <= 0) return; uiText(c, str, x, y + (1 - easeOut(clamp(k, 0, 1))) * 26, { ...o, al: k }); }

// Draw-on brush-pen line with a stable seed, so a held line holds its marks.
const inkLine = (c, pts, p, o = {}) => brush(c, pts, { w: 4, color: ROAM.ink, amp: 1.2, ...o, p });

// Roam card: white rounded panel with a pen outline, popping in as a callout.
function roamCard(c, x, y, w, h, k, seed, body) {
  if (k <= 0) return;
  const s = lerp(.86, 1, easeOutBack(clamp(k, 0, 1)));
  c.save(); c.translate(x + w / 2, y + h / 2); c.scale(s, s); c.translate(-w / 2, -h / 2); c.globalAlpha *= clamp(k * 1.6, 0, 1);
  c.fillStyle = 'rgba(24,32,59,.12)'; c.beginPath(); c.roundRect(6, 10, w, h, 26); c.fill();
  gouache(c, roundRectPath(0, 0, w, h, 26), '#ffffff', 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 2.6;
  wob(c, roundRectPts(0, 0, w, h, 26), .9, seed, true, { pressure: .3, smooth: false });
  body(c, w, h);
  c.restore();
}

// Perimeter of a rounded rectangle as points, for hand-drawn outlines.
function roundRectPts(x, y, w, h, r, step = 8) {
  const out = [], corners = [[x + w - r, y + r, -Math.PI / 2], [x + w - r, y + h - r, 0], [x + r, y + h - r, Math.PI / 2], [x + r, y + r, Math.PI]];
  for (const [cx, cy, a0] of corners) { const n = Math.max(3, Math.round(r * Math.PI / 2 / step)); for (let k = 0; k <= n; k++) { const a = a0 + k / n * Math.PI / 2; out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]); } }
  return out;
}
// Points of a motionPath from its start to fraction u, sampled every `step` units.
function pathUpTo(mp, u, step = 6) {
  const n = Math.max(1, Math.ceil(mp.length * clamp(u, 0, 1) / step)), out = [];
  for (let k = 0; k <= n; k++) out.push(mp.at(u * k / n).p);
  return out;
}

// Whip pan between shots: the frame slides with a short hand-smeared trail.
const _whipLayer = [];
function whipShot(c, off, draw) {
  if (!off) { draw(c); return; }
  if (!_whipLayer.length) _whipLayer.push(layer());
  const L = _whipLayer[0], g = L.getContext('2d');
  g.setTransform(1, 0, 0, 1, 0, 0); g.clearRect(0, 0, L.width, L.height); resetT(g); draw(g);
  resetT(c); c.fillStyle = ROAM.paper; c.fillRect(0, 0, W, H);
  for (let k = 3; k >= 0; k--) { c.globalAlpha = k ? .16 : 1; c.drawImage(L, -off + k * off * .06, 0, W, H); }
  c.globalAlpha = 1;
}
// A finished shot's last frame, rendered once and reused under the next shot's reveal.
const _heldFrames = new Map();
function heldFrame(name, draw) {
  if (!_heldFrames.has(name)) { const L = layer(), g = L.getContext('2d'); resetT(g); draw(g); _heldFrames.set(name, L); }
  return _heldFrames.get(name);
}

// Handwriting that writes on left to right, as a pen would.
function scrawl(c, str, x, y, k, o = {}) {
  if (k <= 0) return;
  const { size = 44, color = ROAM.ink, rot = 0, align = 'left', al = 1 } = o;
  c.save(); c.translate(x, y); c.rotate(rot); c.globalAlpha *= al; c.font = `${size}px ${HAND_FONT}`; c.textAlign = align; c.textBaseline = 'alphabetic';
  const w = c.measureText(str).width, x0 = align === 'center' ? -w / 2 : align === 'right' ? -w : 0;
  c.beginPath(); c.rect(x0 - 12, -size * 1.3, (w + 24) * clamp(k, 0, 1), size * 2); c.clip();
  c.fillStyle = color; c.fillText(str, 0, 0); c.restore();
}
// A thought cloud: an ellipse with scalloped bumps.
function cloudPts(cx, cy, rx, ry, bumps = 9, n = 90) {
  const out = [];
  for (let i = 0; i < n; i++) { const a = i / n * TAU, r = 1 + .09 * Math.abs(Math.sin(a * bumps / 2)); out.push([cx + Math.cos(a) * rx * r, cy + Math.sin(a) * ry * r]); }
  return out;
}
function thoughtCloud(c, cx, cy, rx, ry, k, from, seed, fill = '#ffffff') {
  if (k <= 0) return;
  const s = easeOutBack(clamp(k, 0, 1));
  for (let j = 0; j < 3; j++) {
    const u = (j + 1) / 4, bx = lerp(from[0], cx - rx * .5, u), by = lerp(from[1], cy + ry * .9, u), r = (5 + j * 5) * clamp(k * 3 - j, 0, 1);
    if (r <= 0) continue;
    gouache(c, circPath(bx, by, r), fill, 1); c.strokeStyle = ROAM.ink; c.lineWidth = 2.4; wob(c, ellPts(bx, by, r, r, 0, 20), .4, seed + j, true);
  }
  c.save(); c.translate(cx, cy); c.scale(s, s); c.translate(-cx, -cy);
  const pts = cloudPts(cx, cy, rx, ry);
  gouache(c, polyPath(pts), fill, 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 3; wob(c, pts, .8, seed + 9, true, { pressure: .3 });
  c.restore();
}

// Distance from time: numeric integral of a speed function, a pure function of t.
function integrate(v, t, dt = 1 / 240) { let d = 0; for (let u = 0; u < t; u += dt) d += v(Math.min(u + dt / 2, t)) * Math.min(dt, t - u); return d; }
