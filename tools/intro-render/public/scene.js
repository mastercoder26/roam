import * as THREE from './three.module.js';

// ---- Params (theme colors + render config), passed via query string ----
const params = new URLSearchParams(location.search);
const color = (key, fallback) => {
  const v = params.get(key);
  return new THREE.Color(v ? `#${v}` : fallback);
};
const num = (key, fallback) => {
  const v = params.get(key);
  return v ? Number(v) : fallback;
};

const COLORS = {
  bg: color('bg', '#121212'),
  surface: color('surface', '#1e1e1e'),
  stroke: color('stroke', '#333333'),
  ink: color('ink', '#f1f1f1'),
  accent: color('accent', '#0570eb'),
  safety: color('safety', '#ff9400'),
};

const WIDTH = num('w', 1170);
const HEIGHT = num('h', 2532);
const DURATION = num('duration', 2.4);
const FPS = num('fps', 60);

// ---- Renderer ----
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, preserveDrawingBuffer: true });
renderer.setSize(WIDTH, HEIGHT, false);
renderer.setPixelRatio(1);
renderer.setClearColor(COLORS.bg, 1);
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = COLORS.bg;

const camera = new THREE.PerspectiveCamera(40, WIDTH / HEIGHT, 0.1, 100);

// ---- Lighting: flat, directional, no gradient washes ----
scene.add(new THREE.AmbientLight(COLORS.ink, 0.55));
const key = new THREE.DirectionalLight(0xffffff, 1.1);
key.position.set(2.2, 2.6, 1.8);
scene.add(key);
const rim = new THREE.DirectionalLight(COLORS.accent, 0.35);
rim.position.set(-2, -1, -1.5);
scene.add(rim);

// ---- Globe: low-poly faceted sphere ----
const RADIUS = 1.55;
const globeGeo = new THREE.IcosahedronGeometry(RADIUS, 3);
const globeMat = new THREE.MeshStandardMaterial({
  color: COLORS.surface,
  flatShading: true,
  roughness: 0.85,
  metalness: 0.05,
});
const globe = new THREE.Mesh(globeGeo, globeMat);
scene.add(globe);

// Wireframe shell — the same "map grid" language as the app's atmosphere.
const wireGeo = new THREE.IcosahedronGeometry(RADIUS * 1.004, 2);
const wireMat = new THREE.MeshBasicMaterial({
  color: COLORS.stroke,
  wireframe: true,
  transparent: true,
  opacity: 0.55,
});
const wire = new THREE.Mesh(wireGeo, wireMat);
scene.add(wire);

// ---- Route: a great-circle arc riding just above the globe surface ----
function latLonToVector3(latDeg, lonDeg, radius) {
  const lat = THREE.MathUtils.degToRad(latDeg);
  const lon = THREE.MathUtils.degToRad(lonDeg);
  return new THREE.Vector3(
    radius * Math.cos(lat) * Math.cos(lon),
    radius * Math.sin(lat),
    radius * Math.cos(lat) * Math.sin(lon)
  );
}

// Chosen to sit on the hemisphere the camera sweeps across (see the azimuth
// range in the camera rig below), so the route never rotates out of frame.
const ROUTE_START = latLonToVector3(-8, 118, RADIUS);
const ROUTE_END = latLonToVector3(28, 68, RADIUS);
const ROUTE_MID = latLonToVector3(10, 95, RADIUS * 1.17);

const routeCurve = new THREE.QuadraticBezierCurve3(ROUTE_START, ROUTE_MID, ROUTE_END);
const ROUTE_SEGMENTS = 160;
const routePoints = routeCurve.getPoints(ROUTE_SEGMENTS).map((p) => p.clone().setLength(RADIUS * 1.012));

function tubeForProgress(progress, radiusScale) {
  const count = Math.max(2, Math.round(ROUTE_SEGMENTS * THREE.MathUtils.clamp(progress, 0, 1)));
  const pts = routePoints.slice(0, count + 1);
  if (pts.length < 2) return null;
  const curve = new THREE.CatmullRomCurve3(pts);
  return new THREE.TubeGeometry(curve, Math.max(2, count), 0.028 * radiusScale, 6, false);
}

const routeCoreMat = new THREE.MeshBasicMaterial({ color: COLORS.accent });
const routeGlowMat = new THREE.MeshBasicMaterial({
  color: COLORS.accent,
  transparent: true,
  opacity: 0.28,
  blending: THREE.AdditiveBlending,
  depthWrite: false,
});

let routeCore = null;
let routeGlow = null;
function setRouteProgress(progress) {
  if (routeCore) { scene.remove(routeCore); routeCore.geometry.dispose(); }
  if (routeGlow) { scene.remove(routeGlow); routeGlow.geometry.dispose(); }
  const coreGeo = tubeForProgress(progress, 1);
  if (!coreGeo) return;
  routeCore = new THREE.Mesh(coreGeo, routeCoreMat);
  scene.add(routeCore);
  const glowGeo = tubeForProgress(progress, 2.6);
  routeGlow = new THREE.Mesh(glowGeo, routeGlowMat);
  scene.add(routeGlow);
}

// Waypoint markers, echoing the app's ignition-pulse milestones.
const MILESTONES = [0.22, 0.5, 0.78];
const milestoneGroup = new THREE.Group();
scene.add(milestoneGroup);
const milestoneMeshes = MILESTONES.map((t) => {
  const p = routeCurve.getPoint(t).setLength(RADIUS * 1.014);
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(0.055, 0.011, 6, 10),
    new THREE.MeshBasicMaterial({ color: COLORS.safety, transparent: true, opacity: 0 })
  );
  ring.position.copy(p);
  ring.lookAt(p.clone().multiplyScalar(2));
  milestoneGroup.add(ring);
  return { t, ring, lit: false };
});

// ---- Car: a small low-poly wedge riding the route ----
const car = new THREE.Group();
const bodyMat = new THREE.MeshStandardMaterial({ color: COLORS.ink, flatShading: true, roughness: 0.6 });
const body = new THREE.Mesh(new THREE.BoxGeometry(0.165, 0.057, 0.084), bodyMat);
const cabin = new THREE.Mesh(new THREE.BoxGeometry(0.088, 0.048, 0.066), bodyMat);
cabin.position.set(-0.013, 0.053, 0);
car.add(body, cabin);

const headlightMat = new THREE.MeshBasicMaterial({ color: COLORS.accent });
const headlight = new THREE.Mesh(new THREE.SphereGeometry(0.02, 8, 8), headlightMat);
headlight.position.set(0.088, 0, 0);
car.add(headlight);

const carGlow = new THREE.PointLight(COLORS.accent, 0, 1.1, 2);
carGlow.position.set(0.11, 0.02, 0);
car.add(carGlow);

const tailMat = new THREE.MeshBasicMaterial({ color: COLORS.safety, transparent: true, opacity: 0.9 });
const tail = new THREE.Mesh(new THREE.SphereGeometry(0.015, 8, 8), tailMat);
tail.position.set(-0.088, 0, 0);
car.add(tail);

car.visible = false;
scene.add(car);

function placeCarAt(t) {
  const p = routeCurve.getPoint(t).setLength(RADIUS * 1.02);
  const ahead = routeCurve.getPoint(Math.min(1, t + 0.01)).setLength(RADIUS * 1.02);
  car.position.copy(p);
  const up = p.clone().normalize();
  const forward = ahead.clone().sub(p).normalize();
  const right = new THREE.Vector3().crossVectors(up, forward).normalize();
  const trueForward = new THREE.Vector3().crossVectors(right, up).normalize();
  const m = new THREE.Matrix4().makeBasis(trueForward, up, right);
  car.quaternion.setFromRotationMatrix(m);
}

// ---- Fade overlay for a clean handoff into the native wordmark reveal ----
const fadeGeo = new THREE.PlaneGeometry(2, 2);
const fadeMat = new THREE.MeshBasicMaterial({ color: COLORS.bg, transparent: true, opacity: 0 });
const fadeCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
const fadeScene = new THREE.Scene();
fadeScene.add(new THREE.Mesh(fadeGeo, fadeMat));

// ---- Easing ----
const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);
const easeInOutCubic = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const easeOutBack = (t) => {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
};
const clamp01 = (v) => Math.min(1, Math.max(0, v));
const remap = (t, a, b) => clamp01((t - a) / (b - a));

// ---- Beat timings (fraction of DURATION) ----
const T_GLOBE_IN_END = 0.34 / DURATION;
const T_DRIVE_START = 0.30 / DURATION;
const T_DRIVE_END = 1.68 / DURATION;
const T_HOLD_END = 2.02 / DURATION;
const T_FADE_START = 2.02 / DURATION;

function render(timeSeconds) {
  const t = clamp01(timeSeconds / DURATION);

  // Globe scale-in.
  const globeIn = easeOutBack(remap(t, 0, T_GLOBE_IN_END));
  const scale = THREE.MathUtils.clamp(globeIn, 0.001, 1.08);
  globe.scale.setScalar(scale);
  wire.scale.setScalar(scale);

  // Constant slow spin, the "living planet" read.
  const spin = t * Math.PI * 0.36;

  // Drive progress + route reveal.
  const driveT = easeInOutCubic(remap(t, T_DRIVE_START, T_DRIVE_END));
  setRouteProgress(driveT);
  car.visible = driveT > 0.001 && driveT < 0.999;
  if (car.visible) {
    placeCarAt(driveT);
    carGlow.intensity = 0.35;
  }
  milestoneMeshes.forEach((m) => {
    const lit = driveT >= m.t;
    m.ring.material.opacity = lit ? 0.85 : 0;
    const pulse = lit ? 1 : 0.001;
    m.ring.scale.setScalar(pulse);
  });

  // Only the globe's own surface spins, like terrain under a fixed satellite
  // path — the route, car, and milestones stay put so they never rotate
  // out of the camera's sweep.
  globe.rotation.y = spin;
  wire.rotation.y = spin;

  // Camera: wide establishing -> orbit follow -> pull back hero shot.
  const orbitT = remap(t, 0, T_HOLD_END);
  const azimuth = THREE.MathUtils.lerp(-0.62, 0.30, easeInOutCubic(orbitT));
  const elevation = THREE.MathUtils.lerp(0.22, 0.36, easeInOutCubic(orbitT));
  const distance = THREE.MathUtils.lerp(6.4, 9.0, easeOutCubic(remap(t, T_DRIVE_END, T_HOLD_END)));

  camera.position.set(
    distance * Math.cos(elevation) * Math.sin(azimuth),
    distance * Math.sin(elevation),
    distance * Math.cos(elevation) * Math.cos(azimuth)
  );
  camera.lookAt(0, 0, 0);

  // Fade to canvas color for the handoff to the native lockup.
  const fade = easeInOutCubic(remap(t, T_FADE_START, 1));
  fadeMat.opacity = fade;

  renderer.render(scene, camera);
  if (fade > 0) {
    renderer.autoClear = false;
    renderer.render(fadeScene, fadeCamera);
    renderer.autoClear = true;
  }
}

window.__renderFrame = render;
window.__ready = true;
render(0);
