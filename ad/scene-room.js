'use strict';
// The night before, in his room. Shot 1: he stares at tomorrow's note, worried, then turns to
// his phone. Shot 3: after checking the route, he lets out a breath.
const ROOM = { gx: 760, gy: 880, gs: 1.0, note: [1330, 318], cloud: [1010, 200] };

const NIGHT = {
  dur: 6.0,
  keys: [
    [0.0, pose({ sh: 14, lx: .8, ly: -.6, brow: .9, smile: -.5, phoneY: -128, tilt: -.04 })],
    [1.4, pose({ sh: 22, lx: .9, ly: -.7, brow: 1.1, smile: -.8, phoneY: -124, tilt: -.07, sweat: 1 })],
    [2.7, pose({ sh: 22, lx: .9, ly: -.7, brow: 1.1, smile: -.8, phoneY: -124, tilt: -.07, sweat: 1 })],
    [3.2, pose({ sh: 16, lx: 0, ly: .9, hy: 12, tilt: .07, brow: .8, smile: -.4, phoneY: -248, glow: 1, sweat: .6 })],
    [4.4, pose({ sh: 14, lx: 0, ly: 1, hy: 20, tilt: .08, brow: .7, smile: -.3, phoneY: -262, glow: 1, sweat: .4 })],
  ],
  blinks: [[2.18, 2.3]],
};
const RELIEF = {
  dur: 3.2,
  keys: [
    [0.0, pose({ sh: 14, lx: 0, ly: 1, hy: 20, tilt: .08, brow: .7, smile: -.3, phoneY: -262, glow: 1 })],
    [0.6, pose({ sh: 14, lx: 0, ly: 1, hy: 18, tilt: .06, brow: .1, smile: 0, phoneY: -262, glow: 1 })],
    [1.2, pose({ sh: -10, lx: 0, ly: .2, hy: -8, tilt: -.1, brow: -.35, blink: 1, mouthO: .8, phoneY: -170, glow: .5 })],
    [1.9, pose({ sh: -6, lx: .5, ly: -.4, hy: -4, tilt: -.04, brow: -.3, smile: .9, blush: .6, phoneY: -160, glow: .4 })],
  ],
  blinks: [[2.7, 2.8]],
};

function roomWall(c) {
  c.fillStyle = '#3d4670'; c.fillRect(-200, -200, W + 400, ROOM.gy + 200);
  c.fillStyle = alpha('#ffffff', .035);
  for (let x = 40; x < W; x += 96) c.fillRect(x, 0, 30, ROOM.gy);
  const wx = 110, wy = 150, ww = 330, wh = 380;
  const sky = c.createLinearGradient(0, wy, 0, wy + wh); sky.addColorStop(0, '#141a38'); sky.addColorStop(1, '#2d3563');
  c.fillStyle = sky; c.fillRect(wx, wy, ww, wh);
  for (let k = 0; k < 14; k++) { c.fillStyle = alpha('#fff6d8', .5 + hash(k, 2) * .5); c.beginPath(); c.arc(wx + 20 + hash(k, 3) * (ww - 40), wy + 20 + hash(k, 4) * (wh * .6), 1.2 + hash(k, 5) * 1.6, 0, TAU); c.fill(); }
  gouache(c, circPath(wx + 238, wy + 96, 34), '#f6eccb', 1);
  gouache(c, circPath(wx + 252, wy + 86, 30), '#141a38', 1);
  for (let k = 0; k < 6; k++) { const x = wx + k * 60 - 10, h = 40 + hash(k, 8) * 80; gouache(c, rectPath(x, wy + wh - h, 52, h), '#1b2146', 1); if (hash(k, 9) > .4) { c.fillStyle = '#e8c56a'; c.fillRect(x + 14, wy + wh - h + 16, 8, 10); } }
  c.strokeStyle = '#e9e3d2'; c.lineWidth = 12; c.strokeRect(wx, wy, ww, wh);
  brush(c, [[wx + ww / 2, wy], [wx + ww / 2, wy + wh]], { w: 9, color: '#e9e3d2', seed: 402, taper: 0, amp: .6 });
  brush(c, [[wx, wy + wh * .52], [wx + ww, wy + wh * .52]], { w: 9, color: '#e9e3d2', seed: 403, taper: 0, amp: .6 });
  c.strokeStyle = ROAM.ink; c.lineWidth = 3; wob(c, rectPts(wx - 6, wy - 6, ww + 12, wh + 12), 1, 404, true, { smooth: false });
}

function roomNote(c, tau, extra) {
  const [nx, ny] = ROOM.note;
  c.save(); c.translate(nx, ny); c.rotate(.05);
  c.fillStyle = 'rgba(10,14,30,.3)'; c.fillRect(-140, -118, 300, 270);
  gouache(c, polyPath([[-150, -128], [146, -124], [150, 136], [-146, 140]]), '#f6df76', 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 2.6; wob(c, [[-150, -128], [146, -124], [150, 136], [-146, 140]], .8, 411, true, { smooth: false });
  gouache(c, polyPath([[-46, -142], [48, -138], [46, -110], [-48, -114]]), alpha('#e9e3d2', .8), 1);
  scrawl(c, 'tmrw 5:30pm', -122, -64, sm(.3, 1.0, tau), { size: 44 });
  scrawl(c, 'drive to Wrigley', -122, -8, sm(.9, 1.7, tau), { size: 40 });
  scrawl(c, 'alone.', -122, 52, sm(1.6, 2.1, tau), { size: 44, color: ROAM.red });
  brush(c, [[-122, 64], [-30, 70], [-6, 62]], { w: 4, color: ROAM.red, p: sm(2.0, 2.3, tau), seed: 413 });
  if (extra > 0) {
    brush(c, [[40, 20], [62, 50], [110, -8]], { w: 7, color: ROAM.deep, p: extra, seed: 415, smooth: false });
  }
  c.restore();
}

function roomDesk(c) {
  const top = ROOM.gy;
  gouache(c, rectPath(-200, top, W + 400, H - top + 200), '#8e6242', 1);
  hatch(c, rectPath(0, top, W, H - top), [0, top, W, H - top], { angle: -.15, gap: 14, len: 60, color: ROAM.ink, alpha: .16, width: 1.4, seed: 421, flow: .1 });
  gouache(c, rectPath(0, top, W, 16), '#a8774f', 1);
  brush(c, [[-20, top], [W / 2, top + 2], [W + 20, top]], { w: 4.5, color: ROAM.ink, seed: 422, taper: 0 });
  const lx = 1640;
  gouache(c, polyPath([[lx - 16, top], [lx - 10, top - 170], [lx + 10, top - 170], [lx + 16, top]]), '#4b4f63', 1);
  gouache(c, polyPath([[lx - 90, top - 160], [lx - 50, top - 280], [lx + 50, top - 280], [lx + 90, top - 160]]), '#e4a84a', 1);
  c.strokeStyle = ROAM.ink; c.lineWidth = 3; wob(c, [[lx - 90, top - 160], [lx - 50, top - 280], [lx + 50, top - 280], [lx + 90, top - 160]], .8, 423, true, { smooth: false });
  wob(c, [[lx - 16, top], [lx - 10, top - 162]], .5, 424); wob(c, [[lx + 16, top], [lx + 10, top - 162]], .5, 425);
}

function worryTangle(c, cx, cy, p, seed) {
  const r = rng(seed), pts = [];
  for (let k = 0; k < 16; k++) pts.push([cx + (r() - .5) * 190, cy + (r() - .5) * 90]);
  brush(c, spline(pts, 6), { w: 3.4, color: ROAM.ink, p, seed, amp: 1.2 });
}

function roomScene(c, tau, spec, seed, overlay) {
  const q = twos(tau), { P: P0, id } = poseAt(q, spec.keys);
  const P = spec.blinks.some(([a, b]) => q >= a && q < b) ? { ...P0, blink: 1, happy: 0 } : P0;
  roomWall(c);
  overlay.back?.(c, P);
  drawGuy(c, ROOM.gx, ROOM.gy, ROOM.gs, { ...P, glow: 0 }, seed + id * 100);
  roomDesk(c);
  nightfall(c, .32, '#5a6aa8');
  glow(c, 1640, ROOM.gy - 150, 520, '#ffc76a', .5);
  if (P.glow > 0) {
    const s = ROOM.gs, hx = ROOM.gx + P.hx * s, hy = ROOM.gy + (GUY_HEAD_Y + P.hy - P.sh * .6) * s;
    glow(c, hx, hy + 60, 260, '#9fc0ff', P.glow * .55);
    glow(c, ROOM.gx + P.phoneX * s, ROOM.gy + P.phoneY * s, 150, '#9fc0ff', P.glow * .5);
  }
  overlay.front?.(c, P);
  return P;
}

function nightFrame(c, tau) {
  const push = sm(4.5, 6.0, tau, easeIn), P = poseAt(twos(tau), NIGHT.keys).P;
  const tx = lerp(CX, ROOM.gx, push), ty = lerp(540, ROOM.gy + P.phoneY * ROOM.gs, push);
  cam(c, tx, ty, lerp(1 + tau * .012, 5.2, push));
  roomScene(c, tau, NIGHT, 500, {
    back: g => roomNote(g, tau, 0),
    front: () => {
      const [cx, cy] = ROOM.cloud, k = sm(1.0, 1.4, tau) * (1 - sm(3.0, 3.25, tau));
      thoughtCloud(c, cx, cy, 170, 96, k, [ROOM.gx + 100, ROOM.gy - 560], 431);
      if (k > .6) { worryTangle(c, cx - 20, cy, sm(1.3, 2.6, tau), 437); scrawl(c, '?', cx + 110, cy + 26, sm(2.1, 2.3, tau), { size: 70, color: ROAM.red }); }
    },
  });
}

function reliefFrame(c, tau) {
  cam(c, CX, CY, 1.04);
  roomScene(c, tau, RELIEF, 700, {
    back: g => roomNote(g, 9, sm(2.1, 2.5, tau)),
    front: () => scrawl(c, 'ok. I know where it gets hard.', 760, 130, sm(1.7, 2.9, tau), { size: 52, color: '#f6eccb', rot: -.03, align: 'center' }),
  });
}
