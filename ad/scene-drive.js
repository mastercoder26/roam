'use strict';
// Shot 4: the next day's drive. No app on screen: he remembers the hard part from last night,
// eases off early for the hidden stop, stops smoothly, then pulls away into golden hour.
const DRIVE = { dur: 8.0, v0: 520, vTop: 640, brake: [2.4, 4.0], go: [4.7, 6.3], carX: 760, ground: 884, roadTop: 742, roadBot: 936, lane: 812, carS: 1.15 };

const smoothstep = u => u * u * (3 - 2 * u);
function driveSpeed(t) {
  const { v0, vTop, brake: [b0, b1], go: [g0, g1] } = DRIVE;
  if (t < b0) return v0;
  if (t < b1) return v0 * (1 - smoothstep((t - b0) / (b1 - b0)));
  if (t < g0) return 0;
  if (t < g1) return vTop * smoothstep((t - g0) / (g1 - g0));
  return vTop;
}
const driveDist = t => integrate(driveSpeed, t);
const STOP_X = driveDist(DRIVE.brake[1]) + 214 * DRIVE.carS + 20;
const toScreen = (wx, dist) => wx - dist + DRIVE.carX;

// Nose dips under braking and lifts under acceleration; a small rock after the stop.
function drivePitch(t) {
  const h = 1 / 48, acc = (driveSpeed(t + h) - driveSpeed(t - h)) / (2 * h);
  return -acc * .00007 + settle(t, DRIVE.brake[1], { amp: .012, freq: 1.5, decay: 4.5 });
}

function driveSky(c, dusk, dist) {
  resetT(c);
  const top = dusk < .5 ? mix('#bcd3f3', '#6c6ea6', dusk * 2) : mix('#6c6ea6', '#1d2548', (dusk - .5) * 2);
  const hor = dusk < .5 ? mix('#f6f4ec', '#f7b57a', dusk * 2) : mix('#f7b57a', '#8c5c7a', (dusk - .5) * 2);
  const g = c.createLinearGradient(0, 0, 0, DRIVE.roadTop); g.addColorStop(0, top); g.addColorStop(1, hor);
  c.fillStyle = g; c.fillRect(0, 0, W, DRIVE.roadTop + 4);
  const sx = 520 - dist * .012, sy = 200 + dusk * 560, sun = mix('#ffe39a', '#ff9a52', dusk);
  glow(c, sx, sy, 190, sun, .55);
  gouache(c, circPath(sx, sy, 62), sun, 1);
  c.strokeStyle = alpha(ROAM.ink, .5); c.lineWidth = 2; wob(c, ellPts(sx, sy, 62, 62, 0, 40), 1.2, 44, true);
  for (let k = 0; k < 5; k++) {
    const x = ((k * 520 + 180 - dist * .05) % 2600 + 2600) % 2600 - 300, y = 150 + hash(k, 3) * 190, s = .8 + hash(k, 4) * .6;
    const pts = blob(x, y, 110 * s, 34 * s, 60 + k, { amp: .16, n: 40 });
    gouache(c, polyPath(pts), alpha('#ffffff', .88 - dusk * .5), 1);
    c.strokeStyle = alpha(ROAM.ink, .45); c.lineWidth = 2; wob(c, pts, 1, 80 + k, true, { pressure: .3 });
  }
}

function ridge(c, dist, par, base, amp, seed, fill) {
  const off = dist * par, pts = [[-60, DRIVE.roadTop + 4]];
  for (let sx = -60; sx <= W + 60; sx += 16) { const wx = sx + off; pts.push([sx, base - amp * (.55 + .45 * noise1(wx / 430, seed)) - amp * .3 * noise1(wx / 140, seed + 3)]); }
  pts.push([W + 60, DRIVE.roadTop + 4]);
  gouache(c, polyPath(pts), fill, 1);
  c.save(); c.strokeStyle = alpha(ROAM.ink, .55); c.lineWidth = 2.2; c.lineJoin = 'round'; c.beginPath();
  pts.slice(1, -1).forEach(([x, y], i) => i ? c.lineTo(x, y) : c.moveTo(x, y)); c.stroke(); c.restore();
}

function midItems(dist) {
  const par = .6, off = dist * par, sp = 250, out = [];
  for (let k = Math.floor((off - 400) / sp); k <= Math.ceil((off + W + 400) / sp); k++) {
    const r = hash(k, 91);
    out.push({ k, r, x: k * sp + (hash(k, 92) - .5) * 80 - off, type: r < .36 ? 'house' : 'tree' });
  }
  return out;
}
const HOUSE_WALLS = ['#f6e3c4', '#ecd5da', '#d8e6f1', '#e3ecd4'], HOUSE_ROOFS = ['#c8694c', '#5f74b0', '#8a6c5a', '#3f8a6a'];
function houseGeo(it) { const w = 150 + hash(it.k, 5) * 50, h = 96 + hash(it.k, 6) * 30; return { w, h, win: [[-w * .26, -h * .55], [w * .22, -h * .55]] }; }
function drawHouse(c, it, base) {
  const { w, h, win } = houseGeo(it), wall = HOUSE_WALLS[it.k & 3], roof = HOUSE_ROOFS[(it.k >> 1) & 3], sd = it.k * 17;
  c.save(); c.translate(it.x, base);
  const body = [[-w / 2, 0], [-w / 2, -h], [w / 2, -h], [w / 2, 0]], top = [[-w / 2 - 16, -h], [0, -h - 70], [w / 2 + 16, -h]];
  gouache(c, polyPath(body), wall, 1); gouache(c, polyPath(top), roof, 1);
  hatch(c, polyPath(top), [-w / 2 - 20, -h - 72, w + 40, 74], { angle: -.6, gap: 6, len: 12, color: ROAM.ink, alpha: .2, width: 1, seed: sd });
  for (const [wx, wy] of win) gouache(c, rectPath(wx - 17, wy - 17, 34, 34), '#f9f3dc', 1);
  gouache(c, rectPath(-14, -54, 28, 54), shade(roof, .15), 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 2.4;
  wob(c, body, 1, sd + 1, false, { pressure: .3, smooth: false });
  wob(c, top, 1, sd + 2, false, { pressure: .3, smooth: false });
  c.lineWidth = 1.6;
  for (const [wx, wy] of win) { wob(c, rectPts(wx - 17, wy - 17, 34, 34), .6, sd + 3, true, { smooth: false }); c.beginPath(); c.moveTo(wx, wy - 17); c.lineTo(wx, wy + 17); c.stroke(); }
  wob(c, [[-14, 0], [-14, -54], [14, -54], [14, 0]], .6, sd + 4, false, { smooth: false });
  c.restore();
}
function drawTree(c, it, base) {
  const sd = it.k * 23, h = 90 + hash(it.k, 7) * 60, rx = 58 + hash(it.k, 8) * 28, ry = 62 + hash(it.k, 9) * 30;
  const green = [ROAM.green, '#6fb56b', ROAM.deep, '#8cc27a'][it.k & 3];
  c.save(); c.translate(it.x, base);
  gouache(c, polyPath([[-8, 0], [-6, -h], [6, -h], [9, 0]]), '#8a6a52', 1);
  const crown = blob(0, -h - ry * .6, rx, ry, sd, { amp: .12, n: 44 }), cp = polyPath(crown);
  gouache(c, cp, green, 1);
  hatch(c, cp, [-rx, -h - ry * 1.7, rx * 2, ry * 2.2], { angle: -1.0, gap: 6, len: 12, color: ROAM.ink, alpha: .24, width: 1.1, seed: sd, flow: .3 });
  c.save(); c.clip(cp); c.fillStyle = alpha('#ffffff', .22); c.beginPath(); c.ellipse(-rx * .35, -h - ry, rx * .45, ry * .4, -.4, 0, TAU); c.fill(); c.restore();
  c.strokeStyle = ROAM.ink; c.lineWidth = 2.4; wob(c, crown, 1.2, sd + 1, true, { pressure: .35 });
  c.lineWidth = 2; wob(c, [[-8, 0], [-6, -h + 10]], .6, sd + 2); wob(c, [[9, 0], [6, -h + 10]], .6, sd + 3);
  c.restore();
}

function driveRoad(c, dist) {
  const { roadTop, roadBot, lane } = DRIVE;
  resetT(c);
  c.fillStyle = ROAM.road; c.fillRect(0, roadTop, W, roadBot - roadTop);
  c.fillStyle = alpha(ROAM.ink, .12);
  for (let k = Math.floor((dist - 60) / 29); k <= Math.ceil((dist + W) / 29); k++) {
    const x = k * 29 - dist + (hash(k, 1) - .5) * 20, y = roadTop + 6 + hash(k, 2) * (roadBot - roadTop - 12);
    c.fillRect(x, y, 2 + hash(k, 3) * 5, 1.4);
  }
  c.fillStyle = '#ffffff';
  for (let k = Math.floor((dist - 200) / 150); k <= Math.ceil((dist + W) / 150); k++) { c.beginPath(); c.roundRect(k * 150 - dist, lane - 4, 78, 8, 4); c.fill(); }
  const sx = toScreen(STOP_X, dist);
  if (sx > -60 && sx < W + 60) { c.fillStyle = '#ffffff'; c.beginPath(); c.moveTo(sx, lane + 10); c.lineTo(sx + 16, lane + 10); c.lineTo(sx + 28, roadBot - 22); c.lineTo(sx + 12, roadBot - 22); c.closePath(); c.fill(); }
  c.strokeStyle = ROAM.ink; c.lineWidth = 2.8; c.beginPath(); c.moveTo(0, roadTop); c.lineTo(W, roadTop); c.moveTo(0, roadBot); c.lineTo(W, roadBot); c.stroke();
}

function driveVerge(c, dist) {
  const { roadBot } = DRIVE;
  resetT(c);
  c.fillStyle = ROAM.grass; c.fillRect(0, roadBot + 1.4, W, H - roadBot);
  const par = 1.2, off = dist * par;
  c.strokeStyle = alpha(ROAM.deep, .9); c.lineCap = 'round';
  for (let k = Math.floor((off - 80) / 70); k <= Math.ceil((off + W + 80) / 70); k++) {
    const x = k * 70 - off + (hash(k, 11) - .5) * 40, y = roadBot + 40 + hash(k, 12) * 90, s = .7 + hash(k, 13) * .7;
    c.lineWidth = 2.2; c.beginPath();
    for (const a of [-.5, -.1, .35]) { c.moveTo(x, y); c.quadraticCurveTo(x + a * 10 * s, y - 14 * s, x + a * 26 * s, y - 24 * s); }
    c.stroke();
  }
}

function drawStopSign(c, dist) {
  const x = toScreen(STOP_X + 80, dist), y = 628;
  if (x < -80 || x > W + 80) return;
  c.save();
  c.strokeStyle = ROAM.ink; c.fillStyle = '#9aa0a6'; c.fillRect(x - 5, y, 10, DRIVE.roadBot + 38 - y);
  c.lineWidth = 2; c.strokeRect(x - 5, y, 10, DRIVE.roadBot + 38 - y);
  const oct = Array.from({ length: 8 }, (_, k) => { const a = (k + .5) / 8 * TAU; return [x + Math.cos(a) * 50, y + Math.sin(a) * 50]; });
  gouache(c, polyPath(oct), ROAM.red, 1);
  c.strokeStyle = '#ffffff'; c.lineWidth = 3.5; c.stroke(polyPath(oct.map(([px, py]) => [x + (px - x) * .86, y + (py - y) * .86])));
  c.strokeStyle = ROAM.ink; c.lineWidth = 2.6; wob(c, oct, .8, 55, true, { smooth: false, pressure: .3 });
  uiText(c, 'STOP', x, y + 10, { size: 27, weight: 800, color: '#ffffff', align: 'center', track: 1 });
  c.restore();
}

function drivePuffs(c, tau, dist) {
  const [g0, g1] = DRIVE.go;
  for (let ts = g0 + .05; ts < g1 + .3; ts += .13) {
    const age = tau - ts; if (age <= 0 || age > .9) continue;
    const x = toScreen(driveDist(ts) - 206 * DRIVE.carS, dist) - age * 40, y = DRIVE.ground - 30 - age * 46, r = 7 + age * 28, k = 1 - age / .9;
    gouache(c, circPath(x, y, r), alpha('#eef0f3', .8 * k), 1);
    c.strokeStyle = alpha(ROAM.ink, .5 * k); c.lineWidth = 1.6; wob(c, ellPts(x, y, r, r, 0, 24), .8, Math.round(ts * 100), true);
  }
}

// His memory of last night's check: the circled last stretch, in his own thought cloud.
function driveMemory(c, tau, car) {
  const k = sm(.9, 1.3, tau) * (1 - sm(3.7, 4.0, tau));
  if (k <= 0) return;
  const cx = 1250, cy = 250, from = carPoint(car.x, car.y, DRIVE.carS, car.pitch, 20, -250);
  thoughtCloud(c, cx, cy, 250, 130, k, from, 701);
  if (k < .7) return;
  const src = []; for (let u = .84; u <= 1.0001; u += .005) src.push(routePt(u));
  const xs = src.map(p => p[0]), ys = src.map(p => p[1]), x0 = Math.min(...xs), y0 = Math.min(...ys);
  const s = Math.min(150 / (Math.max(...xs) - x0 || 1), 170 / (Math.max(...ys) - y0 || 1));
  const pts = src.map(([x, y]) => [cx - 130 + (x - x0) * s, cy - 88 + (y - y0) * s]);
  brush(c, pts, { w: 8, color: ROAM.ink, p: sm(1.2, 1.8, tau), seed: 703, taper: 0, amp: .8 });
  const hot = pts[Math.round((ROUTE_DATA.hot[0].u - .84) / .16 * (pts.length - 1))];
  brush(c, ellPts(hot[0], hot[1], 40, 34, -2, 36), { close: true, w: 5, color: ROAM.red, p: sm(1.7, 2.1, tau), seed: 705 });
  scrawl(c, 'easy here.', cx - 20, cy + 10, sm(2.0, 2.6, tau), { size: 48, color: ROAM.red });
  scrawl(c, 'look twice', cx - 10, cy + 64, sm(2.4, 3.0, tau), { size: 38 });
}

function driveFrame(c, tau) {
  const dist = driveDist(tau), dusk = sm(4.0, 8.0, tau) * .42, items = midItems(dist);
  driveSky(c, dusk, dist);
  ridge(c, dist, .12, 610, 110, 31, '#b9d3c9');
  ridge(c, dist, .25, 690, 90, 37, '#9cc59c');
  for (const it of items) (it.type === 'house' ? drawHouse : drawTree)(c, it, DRIVE.roadTop + 2);
  driveRoad(c, dist);
  const tq = twos(tau), v = driveSpeed(tau), moving = v > 4;
  const car = { x: DRIVE.carX, y: DRIVE.ground + (moving ? Math.round(drift(tq, 5, { amp: 1.4, freq: 2.2 }) * 2) / 2 : 0), pitch: drivePitch(tq) };
  if (v > 300) speedLines(c, car.x - 250, car.y - 100, 0, 40 + (Math.floor(tau * 8) % 3), 6, (v - 300) / 340 * .55, ROAM.ink);
  drivePuffs(c, tau, dist);
  drawCar(c, car.x, car.y, { pitch: car.pitch, variant: moving ? Math.floor(tau * 6) % 3 : 0, wheel: dist / (CAR_R * DRIVE.carS), scale: DRIVE.carS });
  driveVerge(c, dist);
  drawStopSign(c, dist);
  driveMemory(c, tau, car);
  scrawl(c, 'next day, 5:30pm', 80, 124, sm(.1, 1.0, tau), { size: 58, al: 1 - sm(2.4, 2.8, tau) });
}
