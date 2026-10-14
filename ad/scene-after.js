'use strict';
// Shot 5: parked at Wrigley. He opens the drive review: Roam's score for the drive he just did.
// Copy follows the app: an 86 grades "Steady", and one hard brake gives the hard-braking summary.
const AFTER = {
  dur: 5.4, gx: 640, gy: 1000, px: 1300, py: 540, sh: 880,
  keys: [
    [0.0, pose({ sh: 6, lx: 0, ly: 1, hy: 16, tilt: .06, brow: .35, smile: .1, phoneY: -205 })],
    [1.6, pose({ sh: 4, lx: 0, ly: 1, hy: 14, tilt: .05, brow: -.1, smile: .5, phoneY: -205 })],
    [2.6, pose({ sh: 2, lx: .9, ly: .1, hy: 4, tilt: -.02, brow: -.2, smile: .5, phoneY: -195 })],
    [3.6, pose({ sh: -4, lx: -.1, ly: 0, hy: 0, tilt: -.05, brow: -.3, smile: .95, blush: .6, phoneY: -185 })],
  ],
  blinks: [[1.1, 1.2], [4.6, 4.7]],
};
AFTER.sw = AFTER.sh * 1206 / 2622;

function afterSetting(c) {
  const g = c.createLinearGradient(0, 0, 0, 930); g.addColorStop(0, '#f6d9b4'); g.addColorStop(1, '#f7efe2');
  c.fillStyle = g; c.fillRect(-100, -100, W + 200, 1040);
  glow(c, 180, 330, 420, '#ffd08a', .6);
  gouache(c, rectPath(-100, 930, W + 200, 300), '#dcdad2', 1);
  brush(c, [[-40, 930], [W / 2, 932], [W + 40, 929]], { w: 4, color: ROAM.ink, seed: 801, taper: 0 });
  for (let x = 60; x < W; x += 180) brush(c, [[x, 934], [x - 30, 1080]], { w: 2.4, color: alpha(ROAM.ink, .3), seed: 802 + x, taper: 0 });
  afterMarquee(c, 90, 250);
}

function afterMarquee(c, x, y) {
  for (const px of [x + 70, x + 330]) {
    gouache(c, rectPath(px, y + 300, 22, 380), '#55607a', 1);
    wob(c, [[px, y + 300], [px, y + 680]], .8, 811 + px, false);
  }
  const board = roundRectPts(x, y, 420, 210, 26, 6), msg = roundRectPts(x + 30, y + 214, 360, 96, 10, 4);
  gouache(c, polyPath(board, true), '#c8322b', 1);
  gouache(c, polyPath(msg, true), '#1d2238', 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 3.2;
  wob(c, board, 1.2, 815, true); wob(c, msg, 1, 816, true);
  uiText(c, 'WRIGLEY FIELD', x + 210, y + 92, { size: 44, weight: 800, color: '#fbf3df', align: 'center' });
  uiText(c, 'HOME OF THE', x + 210, y + 150, { size: 20, weight: 700, color: '#fbf3df', align: 'center', al: .85 });
  uiText(c, 'CHICAGO CUBS', x + 210, y + 182, { size: 26, weight: 800, color: '#fbf3df', align: 'center' });
  uiText(c, 'PARKING  →', x + 210, y + 274, { size: 30, weight: 700, color: '#f5c451', align: 'center' });
}

function afterReview(c, tau) {
  const { px, py, sw, sh } = AFTER, bw = sw + 34, bh = sh + 34, x0 = px - sw / 2 + 30, y0 = py - sh / 2;
  const kin = sm(0, .5, tau, easeOutQuint);
  c.save(); c.translate(0, (1 - kin) * 90); c.globalAlpha = clamp(kin * 1.5, 0, 1);
  const outline = roundRectPts(px - bw / 2, py - bh / 2, bw, bh, 66, 10);
  c.save(); c.fillStyle = 'rgba(24,32,59,.18)'; c.translate(16, 20); c.fill(polyPath(outline)); c.restore();
  gouache(c, polyPath(outline), ROAM.navy, 1);
  c.save(); c.clip(roundRectPath(px - sw / 2, y0, sw, sh, 52));
  c.fillStyle = '#111214'; c.fillRect(px - sw / 2, y0, sw, sh);
  uiText(c, 'Drive review', x0, y0 + 110, { size: 34, weight: 750, color: '#f4f4f5' });
  uiText(c, 'Today, 5:31 PM  ·  24 min', x0, y0 + 144, { size: 19, weight: 500, color: '#8b8d94' });
  const rk = sm(.7, 1.7, tau, easeOutQuint), rcx = px, rcy = y0 + 300;
  c.lineCap = 'round'; c.lineWidth = 18;
  c.strokeStyle = '#26272c'; c.beginPath(); c.arc(rcx, rcy, 104, 0, TAU); c.stroke();
  c.strokeStyle = ROAM.green; c.beginPath(); c.arc(rcx, rcy, 104, -Math.PI / 2, -Math.PI / 2 + TAU * .86 * rk); c.stroke();
  uiText(c, '86', rcx, rcy + 26, { size: 76, weight: 800, color: '#f4f4f5', align: 'center', al: sm(1.2, 1.5, tau) });
  const kc = sm(1.5, 1.8, tau);
  c.fillStyle = alpha(ROAM.green, .22 * kc); c.beginPath(); c.roundRect(rcx - 58, rcy + 128, 116, 42, 21); c.fill();
  uiText(c, 'Steady', rcx, rcy + 157, { size: 21, weight: 700, color: '#7fd18f', align: 'center', al: kc });
  [['11.7', 'mi'], ['24', 'min'], ['38', 'mph top']].forEach(([v, l], i) => {
    const x = x0 + 8 + i * 124, k = sm(1.8 + i * .1, 2.1 + i * .1, tau);
    uiText(c, v, x, y0 + 540, { size: 34, weight: 750, color: '#f4f4f5', al: k });
    uiText(c, l, x, y0 + 568, { size: 17, weight: 500, color: '#8b8d94', al: k });
  });
  const ke = sm(2.2, 2.6, tau);
  c.globalAlpha *= ke;
  c.fillStyle = '#1c1d21'; c.beginPath(); c.roundRect(x0 - 8, y0 + 598, sw - 44, 176, 22); c.fill();
  [['Hard braking', '1', ROAM.amber], ['Sharp corners', '0', '#55595f'], ['Rapid acceleration', '0', '#55595f']].forEach(([l, n, col], i) => {
    const y = y0 + 646 + i * 48;
    c.fillStyle = col; c.beginPath(); c.arc(x0 + 16, y - 7, 7, 0, TAU); c.fill();
    uiText(c, l, x0 + 36, y, { size: 21, weight: 600, color: '#ececee' });
    uiText(c, n, x0 + sw - 80, y, { size: 21, weight: 700, color: '#ececee', align: 'right' });
  });
  uiText(c, 'Focus on fewer hard braking', x0, y0 + 816, { size: 19, weight: 500, color: '#a9abb2' });
  uiText(c, 'events next drive.', x0, y0 + 842, { size: 19, weight: 500, color: '#a9abb2' });
  c.restore();
  c.strokeStyle = ROAM.ink; c.lineWidth = 4.5; wob(c, outline, 1.1, 811, true, { pressure: .4, smooth: false });
  c.restore();
}

function afterFrame(c, tau) {
  paper(c, ROAM.paper, null, 13);
  cam(c, CX, CY, 1.0 + tau * .004);
  afterSetting(c);
  const q = twos(tau), { P: P0, id } = poseAt(q, AFTER.keys);
  const P = AFTER.blinks.some(([a, b]) => q >= a && q < b) ? { ...P0, blink: 1, happy: 0 } : P0;
  drawGuy(c, AFTER.gx, AFTER.gy, 1.0, P, 900 + id * 100);
  afterReview(c, tau);
  const [ex, ey] = [AFTER.px + AFTER.sw / 2 + 10, AFTER.py - AFTER.sh / 2 + 640];
  brush(c, [[ex + 150, ey + 92], [ex + 70, ey + 60], [ex + 8, ey + 8]], { w: 4, color: ROAM.safety, p: sm(3.0, 3.3, tau), seed: 821 });
  scrawl(c, 'one hard brake.', ex + 50, ey + 140, sm(3.2, 3.8, tau), { size: 40, color: ROAM.safety });
  scrawl(c, "I'll take it.", ex + 70, ey + 190, sm(3.7, 4.2, tau), { size: 40 });
}
