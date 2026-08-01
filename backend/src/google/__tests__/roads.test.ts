import { describe, expect, it } from "vitest";
import {
  applySpeedLimitsToSteps,
  buildStepSpeedMap,
  enrichStepSpeeds,
} from "../roads.js";
import type { ParsedRoute } from "../../types.js";

const twoStepRoute: ParsedRoute = {
  distanceMeters: 3_218.68,
  durationSeconds: 180,
  staticDurationSeconds: 180,
  polyline: "",
  bounds: {
    southwest: { lat: 0, lng: 0 },
    northeast: { lat: 1, lng: 1 },
  },
  steps: [
    { distanceMeters: 1_609.34, staticDurationSeconds: 120, maneuver: "DEPART" },
    { distanceMeters: 1_609.34, staticDurationSeconds: 60, maneuver: "STRAIGHT" },
  ],
};

describe("speed-limit step assignment", () => {
  it("keeps posted limits local to their sampled route step", () => {
    const speeds = applySpeedLimitsToSteps(twoStepRoute, [
      { placeId: "local", speedLimit: 25, speedLimitUnit: "MPH", sampleIndex: 0, sampleCount: 4 },
      { placeId: "freeway", speedLimit: 70, speedLimitUnit: "MPH", sampleIndex: 3, sampleCount: 4 },
    ]);

    expect(speeds.get(0)).toBeCloseTo(26, 1);
    expect(speeds.get(1)).toBeCloseTo(68, 1);
  });

  it("falls back to per-step implied speeds when positional coverage is absent", () => {
    const baseline = buildStepSpeedMap(twoStepRoute);
    const speeds = applySpeedLimitsToSteps(twoStepRoute, [
      { placeId: "unknown-position", speedLimit: 70, speedLimitUnit: "MPH" },
    ]);

    expect(speeds.get(0)).toBe(baseline.get(0));
    expect(speeds.get(1)).toBe(baseline.get(1));
  });

  it("reports the distance-weighted portion backed by posted speed limits", () => {
    const enrichment = enrichStepSpeeds(twoStepRoute, [
      { placeId: "local", speedLimit: 25, speedLimitUnit: "MPH", sampleIndex: 0, sampleCount: 4 },
    ]);

    expect(enrichment.postedSpeedLimitCoverage).toBeCloseTo(0.5);
    expect(enrichment.source).toBe("mixed");
    expect(enrichment.stepSpeedsMph.get(0)).toBeCloseTo(26, 1);
  });
});
