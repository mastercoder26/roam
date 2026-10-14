'use strict';
// Roam's car: a friendly blue hatchback in side view, facing right.
// Local units: origin on the road halfway between the wheels, up is negative y.
// The body is a set of whole drawings (7 pitch poses x 3 redrawn line variants),
// compiled once and cached as sprites. Wheels are motor-driven and drawn live.

const CAR_R = 40, CAR_AXLE = -40, CAR_WHEELS = [-128, 132];
const CAR_PITCHES = [-.045, -.03, -.015, 0, .015, .03, .045];
const CAR_COL = {
  body: '#3158D4', shade: '#2141a3', light: '#7d9bf0', glass: '#d3e2fb', tire: '#1b2140', wall: '#4a5378',
  hub: '#e4e8f0', ink: '#141a33', lamp: '#fff1b8', tail: '#D44C42', tag: '#E77B12', skin: '#f2c7a5', hair: '#3a2a22',
};

// Wheel arch traversed rear to front, over the top of the wheel.
function archPts(cx, n = 10) {
  const out = [];
  for (let k = 0; k <= n; k++) { const a = Math.PI + k / n * Math.PI; out.push([cx + 52 * Math.cos(a), CAR_AXLE + 4 + 52 * Math.sin(a)]); }
  return out;
}
const CAR_BODY = [
  [-204, -36], ...archPts(-128), ...archPts(132), [202, -36], [213, -58], [214, -86], [204, -106], [168, -120], [118, -128],
  [88, -134], [52, -174], [12, -195], [-60, -200], [-120, -192], [-170, -150], [-198, -124], [-211, -98], [-210, -62],
];
const CAR_GLASS = [[80, -134], [48, -170], [10, -187], [-60, -191], [-116, -184], [-160, -148], [-178, -134]];
const CAR_PILLAR = [[-50, -134], [-36, -134], [-38, -190], [-54, -190]];
const CAR_TAG = [[-150, -104], [-70, -104], [-70, -82], [-150, -82]];
const CAR_LAMP = ellPts(198, -98, 9, 11, 0, 16);
const CAR_TAIL = [[-210, -108], [-200, -108], [-199, -84], [-209, -84]];
const CAR_MIRROR = [[70, -138], [90, -146], [95, -132], [76, -127]];
const CAR_HEAD = ellPts(12, -160, 15, 16, 0, 18);

const carPressure = [[0, .15], [.15, .9], [.5, 1], [.85, .8], [1, .12]];

// One whole drawing: every landmark rotated about the axle line by the pose's pitch,
// then a small deterministic redraw offset per variant (a new drawing, not a boiling seed).
function carPose(pitch, variant) {
  const ca = Math.cos(pitch), sa = Math.sin(pitch);
  const tf = (pts, id, amp = .9) => pts.map(([x, y], j) => {
    const yy = y - CAR_AXLE, jx = variant ? (hash(j * 7 + id.length * 31, variant * 13) - .5) * 2 * amp : 0, jy = variant ? (hash(j * 11 + id.length * 17, variant * 29) - .5) * 2 * amp : 0;
    return [x * ca - yy * sa + jx, CAR_AXLE + x * sa + yy * ca + jy];
  });
  const g = {
    body: tf(CAR_BODY, 'body'), glass: tf(CAR_GLASS, 'glass'), pillar: tf(CAR_PILLAR, 'pillar', 0), tag: tf(CAR_TAG, 'tag', 0),
    lamp: tf(CAR_LAMP, 'lamp', 0), tail: tf(CAR_TAIL, 'tail', 0), mirror: tf(CAR_MIRROR, 'mirror'), head: tf(CAR_HEAD, 'head', .5),
    hair: tf([[-3, -158], [-2, -168], [3, -178], [14, -182], [26, -175], [30, -163], [22, -169], [10, -170], [2, -164]], 'hair', 0),
    hoodie: tf([[-10, -146], [8, -150], [30, -150], [46, -146], [48, -126], [-12, -126]], 'hoodie', 0),
  };
  const strokes = [];
  const add = (id, points, width, extra = {}) => strokes.push({ id, points: tf(points, id), width, opacity: 1, pressure: carPressure, ...extra });
  add('glass', CAR_GLASS, 2.2, { close: true, corner: .9 });
  add('pillar', CAR_PILLAR, 1.6, { close: true, corner: .6 });
  add('hair', [[-2, -166], [2, -178], [14, -181], [26, -174], [29, -163]], 2.4);
  add('head', CAR_HEAD, 1.8, { close: true });
  add('eye', [[22, -163], [23.5, -160]], 2.6);
  add('arm', [[4, -140], [26, -146], [44, -151]], 2.6);
  add('wheel-grip', [[48, -162], [41, -140]], 3.6);
  add('body', CAR_BODY, 3.4, { close: true, corner: .9 });
  add('seam-back', [[-43, -130], [-44, -92], [-41, -44]], 1.6);
  add('seam-front', [[84, -128], [90, -98], [88, -66]], 1.6);
  add('seam-rear', [[-158, -130], [-164, -100], [-166, -74]], 1.4);
  add('handle-front', [[-22, -114], [2, -114]], 2.6);
  add('handle-rear', [[-136, -114], [-114, -114]], 2.6);
  add('bumper-front', [[176, -56], [212, -56]], 1.6);
  add('bumper-rear', [[-210, -56], [-184, -56]], 1.6);
  add('lamp', CAR_LAMP, 1.8, { close: true });
  add('tail', CAR_TAIL, 1.6, { close: true, corner: .6 });
  add('mirror', CAR_MIRROR, 1.8, { close: true, corner: .7 });
  add('tag', CAR_TAG, 1.4, { close: true, corner: .6 });
  add('shoulder', [[-194, -121], [-100, -127], [40, -128], [168, -116]], 2.2, { color: CAR_COL.light, opacity: .9 });
  add('roof-shine', [[-100, -194], [-40, -197], [0, -193]], 2.4, { color: '#ffffff', opacity: .7 });
  return { geo: g, cel: compileCel({ strokes }, { id: `car-${pitch}-${variant}` }) };
}

// Fills first (paint under the line), then the brush-pen outline on top.
function paintCar(g, pose) {
  const { geo } = pose, body = curvePath(geo.body, true, .9), glass = curvePath(geo.glass, true, .9);
  g.save(); g.lineJoin = 'round';
  gouache(g, body, CAR_COL.body, 1);
  g.save(); g.clip(body);
  const lg = g.createLinearGradient(0, -120, 0, -36); lg.addColorStop(0, alpha(CAR_COL.shade, 0)); lg.addColorStop(1, alpha(CAR_COL.shade, .75));
  g.fillStyle = lg; g.fillRect(-230, -130, 460, 100);
  hatch(g, body, [-220, -95, 440, 60], { angle: -.95, gap: 6, len: 11, jitter: 3, color: CAR_COL.ink, alpha: .22, width: 1.1, seed: 12, flow: .05 });
  g.restore();
  gouache(g, glass, CAR_COL.glass, 1);
  g.save(); g.clip(glass); g.strokeStyle = 'rgba(255,255,255,.85)'; g.lineCap = 'round';
  for (const [x, w] of [[-120, 14], [-92, 6], [30, 12], [52, 5]]) { g.lineWidth = w; g.beginPath(); g.moveTo(x, -130); g.lineTo(x + 48, -196); g.stroke(); }
  g.restore();
  g.save(); g.clip(glass); gouache(g, polyPath(geo.hoodie), CAR_COL.tag, 1); g.restore();
  gouache(g, curvePath(geo.head, true), CAR_COL.skin, 1);
  gouache(g, polyPath(geo.hair), CAR_COL.hair, 1);
  gouache(g, polyPath(geo.pillar), CAR_COL.body, 1);
  gouache(g, polyPath(geo.tag), CAR_COL.tag, 1);
  gouache(g, polyPath(geo.lamp), CAR_COL.lamp, 1);
  gouache(g, polyPath(geo.tail), CAR_COL.tail, 1);
  gouache(g, polyPath(geo.mirror), CAR_COL.body, 1);
  drawCel(g, pose.cel, { material: 'ink', color: CAR_COL.ink });
  const [tx, ty] = geo.tag[3], ang = Math.atan2(geo.tag[1][1] - geo.tag[0][1], geo.tag[1][0] - geo.tag[0][0]);
  g.translate(tx + 40 * Math.cos(ang), ty + 40 * Math.sin(ang) - 6); g.rotate(ang);
  g.fillStyle = '#fff'; g.font = `800 12.5px ${UI_FONT}`; g.textAlign = 'center'; g.letterSpacing = '1px'; g.fillText('NEW DRIVER', 0, 0);
  g.restore();
}

const CAR_SPRITE_BOX = [-250, -250, 500, 290];
const _carSprites = new Map();
function carSprite(pi, variant) {
  const k = `${pi}/${variant}/${S}`;
  if (!_carSprites.has(k)) {
    const [bx, by, bw, bh] = CAR_SPRITE_BOX, res = S * 1.3, cvs = document.createElement('canvas');
    cvs.width = Math.ceil(bw * res); cvs.height = Math.ceil(bh * res);
    const g = cvs.getContext('2d'); g.scale(res, res); g.translate(-bx, -by);
    paintCar(g, carPose(CAR_PITCHES[pi], variant));
    _carSprites.set(k, cvs);
  }
  return _carSprites.get(k);
}
const nearestPitch = p => CAR_PITCHES.reduce((best, v, i) => Math.abs(v - p) < Math.abs(CAR_PITCHES[best] - p) ? i : best, 3);

function drawWheel(c, x, y, a, seed) {
  c.save(); c.translate(x, y);
  c.fillStyle = CAR_COL.tire; c.beginPath(); c.arc(0, 0, CAR_R, 0, TAU); c.fill();
  c.strokeStyle = CAR_COL.wall; c.lineWidth = 2; c.beginPath(); c.arc(0, 0, 30, 0, TAU); c.stroke();
  c.fillStyle = CAR_COL.hub; c.beginPath(); c.arc(0, 0, 21, 0, TAU); c.fill();
  c.rotate(a); c.strokeStyle = CAR_COL.ink; c.lineWidth = 3.4; c.lineCap = 'round'; c.beginPath();
  for (let k = 0; k < 5; k++) { const b = k / 5 * TAU; c.moveTo(Math.cos(b) * 6, Math.sin(b) * 6); c.lineTo(Math.cos(b) * 18, Math.sin(b) * 18); }
  c.stroke(); c.rotate(-a);
  c.strokeStyle = CAR_COL.ink; c.lineWidth = 2.6; wob(c, ellPts(0, 0, CAR_R, CAR_R, 0, 40), 1, seed, true, { pressure: .35 });
  c.restore();
}

// o: pitch (radians, quantised to a drawn pose), variant 0..2, wheel angle, scale, shadow alpha
function drawCar(c, x, y, o = {}) {
  const { pitch = 0, variant = 0, wheel = 0, scale = 1, shadow = .22 } = o;
  c.save(); c.translate(x, y); c.scale(scale, scale);
  if (shadow) { c.fillStyle = alpha(CAR_COL.ink, shadow); c.beginPath(); c.ellipse(0, 3, 214, 11, 0, 0, TAU); c.fill(); }
  CAR_WHEELS.forEach((wx, k) => drawWheel(c, wx, CAR_AXLE, wheel, 70 + k));
  const [bx, by, bw, bh] = CAR_SPRITE_BOX;
  c.drawImage(carSprite(nearestPitch(pitch), variant), bx, by, bw, bh);
  c.restore();
}
// Screen position of a car-local point (headlight beams, tail glow) for a car drawn at (cx, cy).
function carPoint(cx, cy, scale, pitch, lx, ly) {
  const p = CAR_PITCHES[nearestPitch(pitch)], yy = ly - CAR_AXLE;
  return [cx + scale * (lx * Math.cos(p) - yy * Math.sin(p)), cy + scale * (CAR_AXLE + lx * Math.sin(p) + yy * Math.cos(p))];
}
