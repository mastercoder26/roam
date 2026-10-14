'use strict';
// Shot 6: sign-off. ROAM brush-lettered in white on navy, the O is a steering wheel, the car rolls in.
const END = { dur: 5.0, top: 290, bot: 490, x: 559 };
function endLetters() {
  const { top: t, bot: b } = END, R = END.x, O = R + 184, A = O + 244, M = A + 204;
  return {
    strokes: [
      { pts: [[R, b], [R, t]], at: [.9, 1.06], smooth: false },
      { pts: [[R, t], [R + 78, t], [R + 126, t + 40], [R + 126, t + 66], [R + 78, t + 105], [R, t + 105]], at: [1.02, 1.26] },
      { pts: [[R + 58, t + 105], [R + 140, b]], at: [1.2, 1.36], smooth: false },
      { pts: [[A, b], [A + 80, t], [A + 160, b]], at: [1.6, 1.9], smooth: false },
      { pts: [[A + 40, t + 128], [A + 120, t + 128]], at: [1.85, 2.0], smooth: false },
      { pts: [[M, b], [M, t], [M + 85, t + 118], [M + 170, t], [M + 170, b]], at: [1.8, 2.3], smooth: false },
    ],
    wheel: { cx: O + 100, cy: (t + b) / 2, r: 83, at: [1.25, 1.7] },
  };
}
const END_LETTERS = endLetters();

function endWheel(c, wh, tau, rot) {
  const k = sm(wh.at[0], wh.at[1], tau, easeInOutSine);
  if (k <= 0) return;
  c.save(); c.translate(wh.cx, wh.cy); c.rotate(rot);
  brush(c, ellPts(0, 0, wh.r, wh.r, -Math.PI / 2, 64), { close: true, w: 34, color: ROAM.paper, p: k, seed: 201, taper: 0, amp: .8 });
  const ks = sm(1.6, 1.85, tau, easeOut);
  if (ks > 0) {
    gouache(c, circPath(0, 16, 25 * ks), ROAM.paper, 1);
    for (const [ex, ey] of [[-80, -4], [80, -4], [0, 82]]) brush(c, [[0, 16], [ex * ks, 16 + (ey - 16) * ks]], { w: 22, color: ROAM.paper, taper: 0, seed: 210 + ex, smooth: false });
  }
  c.restore();
}

function endCar(tau) {
  const t0 = 2.0, t1 = 3.5, xAt = t => lerp(-360, CX, easeOut(clamp((t - t0) / (t1 - t0), 0, 1)));
  const h = 1 / 48, vAt = t => (xAt(t + h) - xAt(t - h)) / (2 * h), acc = (vAt(tau + h) - vAt(tau - h)) / (2 * h);
  return { x: xAt(tau), v: vAt(tau), pitch: -acc * .000012 + settle(tau, t1, { amp: .015, freq: 1.4, decay: 4 }) };
}

function endFrame(c, tau) {
  resetT(c); c.fillStyle = ROAM.navy; c.fillRect(0, 0, W, H);
  grain(c, rectPath(0, 0, W, H), [0, 0, W, H], 1600, '#ffffff', .05, 13, 1.6);
  const rot = -.4 * Math.sin(Math.PI * sm(2.0, 3.5, tau, easeInOutSine));
  for (const s of END_LETTERS.strokes) brush(c, s.pts, { w: 34, color: ROAM.paper, p: sm(s.at[0], s.at[1], tau, easeInOutSine), seed: 220 + s.at[0] * 100, taper: .2, amp: .8, smooth: s.smooth !== false });
  endWheel(c, END_LETTERS.wheel, tau, rot);
  riseText(c, 'Check the drive before. See how it went after.', CX, 610, sm(2.4, 2.9, tau), { size: 46, weight: 600, color: ROAM.paper, align: 'center', track: -1 });
  scrawl(c, 'the driving coach for new drivers, on iPhone', CX, 672, sm(2.9, 3.6, tau), { size: 34, color: '#9fb4f2', align: 'center' });
  brush(c, [[-40, 904], [W * .5, 906], [W + 40, 903]], { w: 3, color: '#46528a', p: sm(1.7, 2.2, tau), seed: 230 });
  if (tau < 2.0) return;
  const car = endCar(tau), s = .62, ground = 900;
  if (car.v > 500) speedLines(c, car.x - 160, ground - 64, 0, 50 + (Math.floor(tau * 8) % 3), 6, Math.min(.6, (car.v - 500) / 1500), '#9fb4f2');
  glow(c, car.x, ground, 170, ROAM.blue, .5);
  drawCar(c, car.x, ground, { scale: s, pitch: car.pitch, variant: car.v > 5 ? Math.floor(tau * 6) % 3 : 0, wheel: (car.x + 360) / (CAR_R * s), shadow: .35 });
  if ((tau > 3.75 && tau < 3.9) || (tau > 4.02 && tau < 4.2)) { const [lx, ly] = carPoint(car.x, ground, s, car.pitch, 206, -98); glow(c, lx, ly, 120, '#fff3c4', 1); }
}
