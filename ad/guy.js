'use strict';
// The driver: a nervous new driver in an orange hoodie. Each pose is drawn whole from a
// small set of acting controls (shoulder line, head, brows, gaze, mouth, phone). Scenes key
// complete poses, expose them on twos, and keep a drawing's marks for as long as it is held.
const GUY = { skin: '#f1c9a5', skinShade: '#d9a582', hair: '#2a2230', hoodie: ROAM.orange, hoodieShade: '#b85c0c', blush: '#ef8b78', drop: '#9cc8f2' };
const GUY_REST = { sh: 0, hx: 0, hy: 0, tilt: 0, brow: 0, lx: 0, ly: 0, blink: 0, happy: 0, smile: 0, mouthO: 0, phoneX: 0, phoneY: -150, glow: 0, sweat: 0, blush: 0 };
const pose = o => ({ ...GUY_REST, ...o });
const GUY_HEAD_Y = -418;

// keys: [[time, pose], ...]. Eased per segment; returns the pose and the id of the nearest key drawing.
function poseAt(t, keys) {
  if (t <= keys[0][0]) return { P: keys[0][1], id: 0 };
  for (let k = 1; k < keys.length; k++) {
    const [t1, b] = keys[k], [t0, a] = keys[k - 1];
    if (t >= t1) continue;
    const u = easeInOutSine((t - t0) / (t1 - t0)), P = {};
    for (const f in a) P[f] = lerp(a[f], b[f], u);
    return { P, id: u < .5 ? k - 1 : k };
  }
  return { P: keys[keys.length - 1][1], id: keys.length - 1 };
}

function facePts(n = 52) {
  const out = [];
  for (let i = 0; i < n; i++) { const a = i / n * TAU, sn = Math.sin(a); out.push([84 * Math.cos(a) * (1 - .17 * Math.max(0, sn)), sn > 0 ? 106 * sn : 98 * sn]); }
  return out;
}
const GUY_FACE = facePts();
const GUY_HAIR = [[-88, 6], [-96, -52], [-66, -100], [-18, -122], [38, -116], [80, -84], [94, -30], [88, 4], [72, -40], [46, -52], [30, -34], [8, -58], [-18, -40], [-44, -60], [-66, -34]];

function guyHead(c, P, seed) {
  const { lx, ly } = P;
  for (const sx of [-1, 1]) {
    const ear = ellPts(sx * 84, 10, 15, 23, 0, 24);
    gouache(c, polyPath(ear), GUY.skin, 1);
    c.strokeStyle = ROAM.ink; c.lineWidth = 3; wob(c, ear, .6, seed + 3 + sx, true, { pressure: .3 });
  }
  const face = polyPath(GUY_FACE);
  gouache(c, face, GUY.skin, 1);
  c.save(); c.clip(face); c.fillStyle = alpha(GUY.skinShade, .55); c.beginPath(); c.ellipse(-70, 40, 40, 90, .1, 0, TAU); c.fill(); c.restore();
  c.strokeStyle = ROAM.ink; c.lineWidth = 4; wob(c, GUY_FACE, 1, seed + 5, true, { pressure: .45 });
  const hair = spline(GUY_HAIR, 5, true);
  gouache(c, polyPath(hair), GUY.hair, 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 3.4; wob(c, hair, 1, seed + 7, true, { pressure: .35 });
  c.strokeStyle = alpha('#ffffff', .25); c.lineWidth = 3; c.beginPath(); c.moveTo(-40, -96); c.quadraticCurveTo(-4, -110, 30, -100); c.stroke();

  if (P.blush > 0) for (const sx of [-1, 1]) { c.fillStyle = alpha(GUY.blush, P.blush * .45); c.beginPath(); c.ellipse(sx * 52, 44, 17, 9, 0, 0, TAU); c.fill(); }
  const y0 = -28;
  for (const sx of [-1, 1]) {
    const inner = y0 - P.brow * 15, arch = y0 - 6 - Math.max(0, -P.brow) * 6;
    brush(c, [[sx * 58, y0 + 3], [sx * 38, arch], [sx * 15, inner]], { w: 6, color: GUY.hair, seed: seed + 11 + sx, taper: .6, amp: .5 });
    const ex = sx * 34 + lx * 9, ey = 8 + ly * 8;
    if (P.blink > .5) {
      const up = P.happy > .5 ? -1 : .3;
      brush(c, [[ex - 11, ey + 2], [ex, ey + 2 + up * 8], [ex + 11, ey + 2]], { w: 4.5, color: ROAM.ink, seed: seed + 13 + sx, taper: .4, amp: .3 });
    } else {
      const ry = 10.5 * (1 - P.blink * .8);
      c.fillStyle = ROAM.ink; c.beginPath(); c.ellipse(ex, ey, 7.5, ry, 0, 0, TAU); c.fill();
      c.fillStyle = '#ffffff'; c.beginPath(); c.arc(ex + 2.5, ey - 3.5, 2.2, 0, TAU); c.fill();
    }
  }
  const nx = lx * 7;
  brush(c, [[nx + 4, 20], [nx - 7, 42], [nx + 5, 46]], { w: 3.4, color: alpha(ROAM.ink, .8), seed: seed + 17, taper: .5, amp: .3, smooth: false });
  const mx = lx * 6, my = 72;
  if (P.mouthO > .2) {
    const m = ellPts(mx, my, 5 + 7 * P.mouthO, 5 + 9 * P.mouthO, 0, 22);
    gouache(c, polyPath(m), '#6b2f33', 1);
    c.strokeStyle = ROAM.ink; c.lineWidth = 3; wob(c, m, .4, seed + 19, true);
  } else {
    const pts = [];
    for (let k = 0; k <= 10; k++) { const u = k / 10; pts.push([mx - 20 + 40 * u, my + P.smile * 12 * Math.sin(Math.PI * u) + Math.min(0, P.smile) * -4 * Math.sin(TAU * 1.5 * u)]); }
    brush(c, pts, { w: 4.5, color: ROAM.ink, seed: seed + 21, taper: .5, amp: .3 });
  }
  if (P.sweat > 0) {
    const s = P.sweat, drop = [[0, -22], [9, -4], [8, 6], [0, 11], [-8, 6], [-9, -4]].map(([x, y]) => [100 + x * s, -34 + y * s + (1 - s) * -10]);
    gouache(c, polyPath(spline(drop, 3, true)), GUY.drop, 1);
    c.strokeStyle = ROAM.ink; c.lineWidth = 2.4; wob(c, drop, .3, seed + 23, true);
  }
}

// x, y: the point on the desk (or frame edge) under his chest; s: scale.
function drawGuy(c, x, y, s, P, seed = 1) {
  c.save(); c.translate(x, y); c.scale(s, s);
  const sh = P.sh, top = -300 - sh;
  const torso = [[-262, 80], [-252, -110], [-226, -226 - sh], [-150, -280 - sh * 1.1], [-56, top], [56, top], [150, -280 - sh * 1.1], [226, -226 - sh], [252, -110], [262, 80]];
  const tp = polyPath(spline(torso, 6));
  const hx = P.hx, hy = GUY_HEAD_Y + P.hy - sh * .6;

  gouache(c, polyPath([[hx - 32, hy + 70], [hx + 32, hy + 70], [38, top + 30], [-38, top + 30]]), GUY.skinShade, 1);
  gouache(c, tp, GUY.hoodie, 1);
  c.save(); c.clip(tp);
  hatch(c, tp, [-270, top - 10, 150, 400], { angle: -.9, gap: 8, len: 16, color: ROAM.ink, alpha: .22, width: 1.3, seed: seed + 31, flow: .2 });
  c.fillStyle = alpha(GUY.hoodieShade, .5); c.beginPath(); c.ellipse(0, top + 40, 120, 60, 0, 0, TAU); c.fill();
  c.restore();
  const hood = spline([[-118, top + 6], [-78, top + 58], [0, top + 82], [78, top + 58], [118, top + 6]], 6);
  brush(c, hood, { w: 5, color: ROAM.ink, seed: seed + 33, taper: .3 });
  for (const sx of [-1, 1]) {
    brush(c, [[sx * 26, top + 74], [sx * 30, top + 118], [sx * 27, top + 150]], { w: 4, color: '#f7efe2', seed: seed + 35 + sx, taper: 0, amp: .4 });
    c.fillStyle = ROAM.ink; c.fillRect(sx * 27 - 3, top + 148, 6, 12);
  }
  c.strokeStyle = ROAM.ink; c.lineWidth = 4.5; wob(c, torso, 1.1, seed + 37, false, { pressure: .45 });

  c.save(); c.translate(hx, hy); c.rotate(P.tilt); guyHead(c, P, seed); c.restore();
  if (P.glow > 0) glow(c, hx + P.phoneX * .3, hy + 40, 210, '#a9c8ff', P.glow * .45);

  const px = P.phoneX, py = P.phoneY;
  for (const sx of [-1, 1]) {
    const arm = [[sx * 232, -196 - sh], [sx * 238, -40], [sx * 150, py + 70], [px + sx * 60, py + 26]];
    const a = spline(arm, 6), line = () => { c.beginPath(); a.forEach(([x, y], i) => i ? c.lineTo(x, y) : c.moveTo(x, y)); c.stroke(); };
    c.save(); c.lineCap = 'round'; c.lineJoin = 'round';
    c.strokeStyle = ROAM.ink; c.lineWidth = 70; line();
    c.strokeStyle = GUY.hoodie; c.lineWidth = 62; line();
    c.restore();
    const [wx, wy] = a[a.length - 6];
    brush(c, [[wx - 18, wy - 24], [wx + 18, wy + 24]], { w: 3.4, color: ROAM.ink, seed: seed + 45 + sx, amp: .4 });
    brush(c, [[sx * 212, -160 - sh], [sx * 218, -60]], { w: 3, color: alpha(ROAM.ink, .35), seed: seed + 47 + sx, amp: .4 });
  }
  const ph = roundRectPts(px - 48, py - 88, 96, 176, 18, 6);
  gouache(c, polyPath(ph), ROAM.navy, 1);
  c.fillStyle = '#2c3a66'; c.beginPath(); c.roundRect(px - 36, py - 76, 34, 34, 10); c.fill();
  c.strokeStyle = ROAM.ink; c.lineWidth = 3.4; wob(c, ph, .6, seed + 47, true, { smooth: false });
  if (P.glow > 0) { c.save(); c.globalCompositeOperation = 'screen'; c.strokeStyle = alpha('#a9c8ff', P.glow * .5); c.lineWidth = 5; c.stroke(polyPath(ph)); c.restore(); }
  for (const sx of [-1, 1]) {
    const hand = blob(px + sx * 50, py + 22, 26, 34, seed + 51 + sx, { amp: .08, n: 30 });
    gouache(c, polyPath(hand), GUY.skin, 1);
    c.strokeStyle = ROAM.ink; c.lineWidth = 3.2; wob(c, hand, .6, seed + 53 + sx, true, { pressure: .3 });
    for (let f = 0; f < 3; f++) brush(c, [[px + sx * 30, py + 2 + f * 13], [px + sx * 44, py + 4 + f * 13]], { w: 2.6, color: alpha(ROAM.ink, .7), seed: seed + 55 + f + sx * 5, taper: .4, amp: .2, smooth: false });
  }
  c.restore();
}
