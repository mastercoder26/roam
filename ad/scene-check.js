'use strict';
// Shot 2: he checks tomorrow's drive. The phone shows the real Roam route screen; his thumb taps
// Analyze; the scored route (real geometry, score and hotspots) is sketched out beside it.
registerPhoto('appRoute', { src: APP_ROUTE_SRC, w: 1206, h: 2622 });
const CHECK = { dur: 7.4, px: 540, py: 545, sh: 900, box: [920, 330, 880] };
CHECK.sw = CHECK.sh * 1206 / 2622;
const onScreen = (u, v) => [CHECK.px - CHECK.sw / 2 + u * CHECK.sw, CHECK.py - CHECK.sh / 2 + v * CHECK.sh];
const routePt = u => { const p = ROUTE_DATA.pts, f = clamp(u, 0, 1) * (p.length - 1), i = Math.min(p.length - 2, Math.floor(f)), t = f - i, [x0, y0, s] = CHECK.box; return [x0 + lerp(p[i][0], p[i + 1][0], t) * s, y0 + lerp(p[i][1], p[i + 1][1], t) * s]; };
function routeHeat(u) { let d = 0; for (const h of ROUTE_DATA.hot) d = Math.max(d, h.d * Math.max(0, 1 - Math.abs(u - h.u) / .035)); return d; }
const heatColor = d => d > .7 ? ROAM.red : d > .5 ? ROAM.orange : d > .38 ? ROAM.amber : ROAM.green;

function checkPhone(c, tau) {
  const { px, py, sw, sh } = CHECK, bw = sw + 34, bh = sh + 34;
  const outline = roundRectPts(px - bw / 2, py - bh / 2, bw, bh, 66, 10);
  c.save(); c.fillStyle = 'rgba(24,32,59,.18)'; c.translate(16, 20); c.fill(polyPath(outline)); c.restore();
  gouache(c, polyPath(outline), ROAM.navy, 1);
  const screen = roundRectPath(px - sw / 2, py - sh / 2, sw, sh, 52);
  c.save(); c.clip(screen);
  c.drawImage(PHOTOS.appRoute.img, px - sw / 2, py - sh / 2, sw, sh);
  const [bx, by] = onScreen(.5, .877), press = sm(1.62, 1.68, tau) * (1 - sm(1.82, 1.95, tau));
  if (press > 0) { c.fillStyle = alpha('#000000', .22 * press); c.beginPath(); c.roundRect(bx - 200, by - 30, 400, 60, 30); c.fill(); }
  const rp = sm(1.66, 2.2, tau, u => u);
  if (rp > 0 && rp < 1) { c.strokeStyle = alpha('#ffffff', .8 * (1 - rp)); c.lineWidth = 4; c.beginPath(); c.arc(bx, by, 20 + rp * 140, 0, TAU); c.stroke(); }
  checkResultScreen(c, tau);
  c.restore();
  c.strokeStyle = ROAM.ink; c.lineWidth = 4.5; wob(c, outline, 1.1, 601, true, { pressure: .4, smooth: false });
  brush(c, [[px + bw / 2 + 2, py - 260], [px + bw / 2 + 2, py - 170]], { w: 7, color: ROAM.ink, seed: 603, taper: 0 });
}

// The results screen, drawn in the app's dark theme from the real analysis.
function checkResultScreen(c, tau) {
  const load = sm(2.05, 2.25, tau), res = sm(2.6, 2.85, tau);
  if (load <= 0) return;
  const { px, py, sw, sh } = CHECK, x0 = px - sw / 2 + 30, y0 = py - sh / 2;
  c.fillStyle = alpha('#111214', load * (res > 0 ? 1 : .86)); c.fillRect(px - sw / 2, y0, sw, sh);
  if (res <= 0) {
    const a = tau * 7; c.strokeStyle = '#e8e8e8'; c.lineWidth = 6; c.lineCap = 'round';
    c.beginPath(); c.arc(px, py, 30, a, a + 4.2); c.stroke(); return;
  }
  c.save(); c.globalAlpha = res;
  uiText(c, 'Oak Park  →  Wrigley Field', x0, y0 + 118, { size: 19, weight: 600, color: '#9a9ca3' });
  uiText(c, 'Tomorrow, 5:30 PM', x0, y0 + 146, { size: 19, weight: 500, color: '#6f7178' });
  uiText(c, `${ROUTE_DATA.score}`, x0, y0 + 300, { size: 150, weight: 800, color: '#f4f4f5', track: -4 });
  uiText(c, '/10', x0 + 96, y0 + 296, { size: 40, weight: 700, color: '#6f7178' });
  c.fillStyle = alpha(ROAM.red, .22); c.beginPath(); c.roundRect(x0 + 190, y0 + 236, 104, 46, 23); c.fill();
  uiText(c, ROUTE_DATA.label, x0 + 242, y0 + 268, { size: 23, weight: 700, color: '#ff8a7d', align: 'center' });
  uiText(c, `${ROUTE_DATA.miles} mi  ·  ${ROUTE_DATA.minutes} min`, x0, y0 + 346, { size: 21, weight: 600, color: '#c9cad0' });
  c.fillStyle = '#1c1d21'; c.beginPath(); c.roundRect(x0 - 8, y0 + 382, sw - 44, 250, 22); c.fill();
  uiText(c, 'Why it scores this way', x0 + 12, y0 + 424, { size: 19, weight: 700, color: '#9a9ca3' });
  ['Unprotected left turns', 'Turns close together', 'Dense decision windows'].forEach((r, i) => {
    const k = sm(2.95 + i * .18, 3.2 + i * .18, tau), y = y0 + 478 + i * 50;
    c.fillStyle = alpha(i ? ROAM.amber : ROAM.red, k); c.beginPath(); c.arc(x0 + 22, y - 7, 7, 0, TAU); c.fill();
    uiText(c, r, x0 + 44, y, { size: 22, weight: 600, color: '#ececee', al: k });
  });
  c.restore();
}

function checkThumb(c, tau) {
  const [bx, by] = onScreen(.5, .877), inn = sm(1.15, 1.62, tau, easeOut), out = sm(1.95, 2.45, tau, easeIn);
  const k = inn * (1 - out); if (k <= 0) return;
  const press = sm(1.62, 1.68, tau) * (1 - sm(1.82, 1.95, tau));
  const tip = [bx + 28, by + 10 + press * 5], base = [bx + 420, by + 460], p = lerp(1.4, 0, k);
  const tx = tip[0] + (base[0] - tip[0]) * p * .5, ty = tip[1] + (base[1] - tip[1]) * p * .5, a = Math.atan2(base[1] - tip[1], base[0] - tip[0]);
  c.save(); c.translate(tx, ty); c.rotate(a);
  const th = [[-6, 0], [4, -34], [60, -44], [260, -54], [420, -70], [420, 70], [260, 50], [60, 38], [4, 30]];
  const pts = spline(th, 6, true);
  gouache(c, polyPath(pts), GUY.skin, 1);
  c.save(); c.clip(polyPath(pts)); c.fillStyle = alpha(GUY.skinShade, .6); c.fillRect(0, 12, 440, 80); c.restore();
  c.strokeStyle = ROAM.ink; c.lineWidth = 4; wob(c, pts, .8, 611, true, { pressure: .4 });
  const nail = ellPts(30, -8, 24, 17, 0, 24);
  gouache(c, polyPath(nail), '#f8ddc8', 1); c.lineWidth = 2.4; wob(c, nail, .4, 612, true);
  brush(c, [[150, -40], [160, -10], [150, 20]], { w: 2.6, color: alpha(ROAM.ink, .5), seed: 613, taper: .5 });
  gouache(c, polyPath([[330, -90], [460, -110], [460, 110], [330, 90]]), GUY.hoodie, 1);
  c.lineWidth = 4; wob(c, [[330, -90], [330, 90]], .8, 614);
  c.restore();
}

function checkMap(c, tau) {
  const [x0, y0, s] = CHECK.box, k = sm(2.3, 2.8, tau);
  if (k <= 0) return;
  c.save(); c.globalAlpha = k;
  c.strokeStyle = alpha(ROAM.ink, .1); c.lineWidth = 1.6;
  for (let x = x0 - 40; x < x0 + s + 40; x += 46) { c.beginPath(); c.moveTo(x + hash(x, 1) * 4, y0 - 70); c.lineTo(x - hash(x, 2) * 4, y0 + s * .6 + 90); c.stroke(); }
  for (let y = y0 - 70; y < y0 + s * .6 + 90; y += 46) { c.beginPath(); c.moveTo(x0 - 40, y + hash(y, 3) * 4); c.lineTo(x0 + s + 40, y - hash(y, 4) * 4); c.stroke(); }
  const lake = [[1858, 180], [1846, 360], [1862, 560], [1850, 760], [1866, 960], [W + 40, 960], [W + 40, 180]];
  wash(c, polyPath(spline(lake, 8)), '#9cc4ea', { al: .7, seed: 621 });
  c.restore();
  scrawl(c, 'lake', 1888, 640, k, { size: 30, color: '#4f7fb3', rot: -Math.PI / 2, align: 'center' });
}

function checkRoute(c, tau) {
  const p = sm(2.6, 4.2, tau, easeInOutSine);
  if (p <= 0) return;
  const n = Math.max(2, Math.ceil(p * 320)), pts = [], cols = [];
  for (let k = 0; k <= n; k++) { const u = k / n * p; pts.push(routePt(u)); cols.push(heatColor(routeHeat(u))); }
  c.save(); c.lineCap = 'round'; c.lineJoin = 'round';
  c.strokeStyle = ROAM.ink; c.lineWidth = 19; c.beginPath(); pts.forEach(([x, y], i) => i ? c.lineTo(x, y) : c.moveTo(x, y)); c.stroke();
  c.lineWidth = 11;
  for (let i = 1; i < pts.length; i++) { c.strokeStyle = cols[i]; c.beginPath(); c.moveTo(...pts[i - 1]); c.lineTo(...pts[i]); c.stroke(); }
  c.restore();
  const [sx, sy] = routePt(0);
  gouache(c, circPath(sx, sy, 13), '#ffffff', 1); c.strokeStyle = ROAM.ink; c.lineWidth = 4; wob(c, ellPts(sx, sy, 13, 13, 0, 20), .5, 631, true);
  scrawl(c, 'Oak Park', sx - 10, sy + 64, sm(2.6, 3.1, tau), { size: 36 });
  const kb = sm(4.1, 4.4, tau, u => u);
  if (kb > 0) {
    const [ex, ey] = routePt(1), s = easeOutBack(kb), pin = [[0, 0], [-18, -28], [-14, -46], [0, -54], [14, -46], [18, -28]];
    c.save(); c.translate(ex, ey); c.scale(s, s);
    gouache(c, polyPath(spline(pin, 3, true)), ROAM.blue, 1);
    c.fillStyle = '#fff'; c.beginPath(); c.arc(0, -36, 7, 0, TAU); c.fill();
    c.strokeStyle = ROAM.ink; c.lineWidth = 3; wob(c, pin, .5, 633, true);
    c.restore();
    scrawl(c, 'Wrigley', ex - 20, ey - 70, sm(4.2, 4.6, tau), { size: 36, align: 'right' });
  }
}

function checkNotes(c, tau) {
  const [hx, hy] = routePt(ROUTE_DATA.hot[0].u), k1 = sm(5.0, 5.4, tau);
  if (k1 > 0) {
    brush(c, ellPts(hx, hy, 52, 46, -2, 44), { close: true, w: 5, color: ROAM.red, p: k1, seed: 651 });
    brush(c, [[1650, 402], [1690, 392], [1712, 382]], { w: 4, color: ROAM.red, p: sm(5.2, 5.4, tau), seed: 653 });
    scrawl(c, 'back-to-back turns', 1640, 400, sm(5.3, 5.9, tau), { size: 38, color: ROAM.red, align: 'right' });
    scrawl(c, 'the last 0.3 mi', 1640, 446, sm(5.7, 6.1, tau), { size: 34, color: ROAM.ink, align: 'right' });
  }
  const [ax, ay] = routePt(.334), k2 = sm(5.8, 6.2, tau);
  if (k2 > 0) {
    brush(c, ellPts(ax, ay, 36, 32, -2, 36), { close: true, w: 4.5, color: ROAM.orange, p: k2, seed: 661 });
    brush(c, [[ax - 4, ay - 94], [ax + 2, ay - 60], [ax, ay - 40]], { w: 4, color: ROAM.orange, p: sm(6.0, 6.2, tau), seed: 663 });
    scrawl(c, 'unprotected lefts', ax, ay - 110, sm(6.1, 6.7, tau), { size: 36, color: ROAM.safety, align: 'center' });
  }
}

function checkFrame(c, tau) {
  paper(c, ROAM.paper, null, 11);
  cam(c, CX, CY, 1 + tau * .004);
  checkMap(c, tau);
  checkRoute(c, tau);
  checkPhone(c, tau);
  checkThumb(c, tau);
  checkNotes(c, tau);
}
