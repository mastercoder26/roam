import { scoreRoutes } from "./src/scoring/index.js";
import { neutralConditions } from "./src/enrichment/index.js";
import type { ParsedRoute } from "./src/types.js";

const route: ParsedRoute = {
  distanceMeters: 16093,
  durationSeconds: 2400,
  staticDurationSeconds: 2100,
  trafficTimingAvailable: true,
  polyline: "encoded_urban_polyline",
  bounds: { southwest: { lat: 40.71, lng: -74.01 }, northeast: { lat: 40.76, lng: -73.97 } },
  steps: [
    { distanceMeters: 200, staticDurationSeconds: 60, maneuver: "DEPART" },
    { distanceMeters: 400, staticDurationSeconds: 90, maneuver: "TURN_LEFT" },
    { distanceMeters: 300, staticDurationSeconds: 75, maneuver: "TURN_RIGHT" },
    { distanceMeters: 350, staticDurationSeconds: 80, maneuver: "TURN_LEFT" },
  ],
};

const { primary } = scoreRoutes([route], [{ conditions: neutralConditions(), departureLocalMinutes: 1065 }]);
const p = JSON.parse(JSON.stringify(primary));

const checks: Array<[string, boolean]> = [
  ["distanceMeters", Number.isInteger(p.distanceMeters)],
  ["durationSeconds", Number.isInteger(p.durationSeconds)],
  ["staticDurationSeconds", Number.isInteger(p.staticDurationSeconds)],
  ["trafficDelaySeconds", Number.isInteger(p.trafficDelaySeconds)],
  ["conditions.road.constructionZones", Number.isInteger(p.conditions?.road?.constructionZones)],
  ["conditions.turns.unprotectedLeftTurns", Number.isInteger(p.conditions?.turns?.unprotectedLeftTurns)],
  ["hotspots[0].segmentIndex", Number.isInteger(p.hotspots?.[0]?.segmentIndex)],
  ["hotspots[0].cumulativeSecondsFromStart", Number.isInteger(p.hotspots?.[0]?.cumulativeSecondsFromStart)],
];

console.log("=== Int field checks ===");
for (const [field, isInt] of checks) {
  console.log(`${field}: isInteger=${isInt}, value=${JSON.stringify(p[field.split(".")[0]])?.slice(0,40)}`);
}
console.log("\n=== conditions.road keys ===", Object.keys(p.conditions?.road ?? {}));
console.log("\n=== First demand ===\n" + JSON.stringify(p.routeDemands?.[0], null, 2));
console.log("\n=== uncertainty ===\n" + JSON.stringify(p.uncertainty, null, 2));
console.log("\n=== top-level keys ===", Object.keys(p));
