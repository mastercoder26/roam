import { describe, expect, it } from "vitest";
import type { ParsedRoute, RouteStep } from "../../types.js";
import { scoreRoute } from "../index.js";
import { computeHighwayShare, computeTurnClustering } from "../signals.js";
import { circadianPenaltyAtHour } from "../fatigue.js";
import { highwayRoute } from "./fixtures/highway-route.js";
import { urbanRoute } from "./fixtures/urban-route.js";
import { trafficHeavyRoute } from "./fixtures/traffic-route.js";
import { mergeClusterRoute } from "./fixtures/merge-cluster-route.js";
import { turnClusterRoute } from "./fixtures/turn-cluster-route.js";

function route(steps: RouteStep[], trafficRatio = 1): ParsedRoute {
  const distanceMeters = steps.reduce((sum, s) => sum + s.distanceMeters, 0);
  const staticDurationSeconds = steps.reduce((sum, s) => sum + s.staticDurationSeconds, 0);
  return {
    ...highwayRoute,
    distanceMeters,
    staticDurationSeconds,
    durationSeconds: staticDurationSeconds * trafficRatio,
    steps,
  };
}

const clustering = (steps: RouteStep[]) =>
  computeTurnClustering(
    steps,
    steps.reduce((sum, s) => sum + s.distanceMeters, 0)
  );

const step = (
  distanceMeters: number,
  mph: number,
  maneuver?: string
): RouteStep => ({
  distanceMeters,
  staticDurationSeconds: distanceMeters / (mph / 2.237),
  maneuver,
});

describe("hybrid-v7 model behaviour", () => {
  it("places a maneuver where its step begins", () => {
    // Two turns 100 m apart, the second followed by a long straight step.
    // Measured at step ends they looked 5 km apart and were not a close pair.
    const result = clustering([
      step(500, 25, "DEPART"),
      step(100, 25, "TURN_LEFT"),
      step(5000, 25, "TURN_RIGHT"),
    ]);
    expect(result.closeTurnPairs).toBe(1);
  });

  it("gives a lone turn no spacing pressure, so adding a turn never lowers it", () => {
    const one = clustering([step(500, 25, "DEPART"), step(3000, 25, "TURN_LEFT")]);
    const two = clustering([
      step(500, 25, "DEPART"),
      step(3000, 25, "TURN_LEFT"),
      step(3000, 25, "TURN_RIGHT"),
    ]);
    expect(one.turnSpacingPressure).toBe(0);
    expect(two.turnSpacingPressure).toBeGreaterThanOrEqual(one.turnSpacingPressure);
  });

  it("does not treat a long slow straight as highway", () => {
    expect(computeHighwayShare([step(4000, 25, "STRAIGHT")]).highwayShare).toBe(0);
    expect(computeHighwayShare([step(4000, 65, "STRAIGHT")]).highwayShare).toBe(1);
  });

  it("has a continuous circadian curve", () => {
    for (let hour = 0; hour < 24; hour += 0.05) {
      const jump = Math.abs(
        circadianPenaltyAtHour(hour + 0.05) - circadianPenaltyAtHour(hour)
      );
      expect(jump).toBeLessThan(0.05);
    }
    expect(circadianPenaltyAtHour(24)).toBeCloseTo(circadianPenaltyAtHour(0), 6);
    expect(circadianPenaltyAtHour(3)).toBeGreaterThan(circadianPenaltyAtHour(12));
  });

  it("does not jump when departure crosses 22:00 or 06:00 by a minute", () => {
    for (const minute of [22 * 60, 6 * 60, 15 * 60, 18 * 60, 8 * 60]) {
      const before = scoreRoute(urbanRoute, { departureLocalMinutes: minute - 1 });
      const after = scoreRoute(urbanRoute, { departureLocalMinutes: minute });
      expect(Math.abs(after.score - before.score)).toBeLessThanOrEqual(0.1);
    }
  });

  it("scores a drive in the dark above the same drive at midday", () => {
    const day = scoreRoute(highwayRoute, { departureLocalMinutes: 12 * 60 });
    const night = scoreRoute(highwayRoute, { departureLocalMinutes: 23 * 60 });
    expect(night.score).toBeGreaterThan(day.score);
    expect(night.contributions.some((c) => c.factor === "night")).toBe(true);
    expect(day.contributions.some((c) => c.factor === "night")).toBe(false);
  });

  it("never lowers the score when a protected left is added", () => {
    const conditions = (protectedLeftTurns: number) => ({
      weather: { available: false },
      road: { available: false },
      turns: {
        available: true,
        unprotectedLeftTurns: 2,
        protectedLeftTurns,
        unprotectedTurnShare: 2 / (2 + protectedLeftTurns),
      },
      sources: [],
    });
    const without = scoreRoute(urbanRoute, { conditions: conditions(0) as never });
    const withProtected = scoreRoute(urbanRoute, { conditions: conditions(4) as never });
    expect(withProtected.uncalibratedScore!).toBeGreaterThanOrEqual(without.uncalibratedScore!);
  });

  it("damps a large relative delay that is only seconds long", () => {
    // 33% slower on a ~2 minute hop vs. on a ~40 minute drive.
    const shortSteps = [step(300, 30, "DEPART"), step(1500, 30, "TURN_RIGHT")];
    const longSteps = [step(300, 30, "DEPART"), step(32000, 30, "TURN_RIGHT")];
    const trafficPoints = (steps: RouteStep[]) => {
      const jammed = scoreRoute(route(steps, 1.33));
      const free = scoreRoute(route(steps, 1));
      return jammed.uncalibratedScore! - free.uncalibratedScore!;
    };
    expect(trafficPoints(longSteps)).toBeGreaterThan(trafficPoints(shortSteps) + 0.5);
  });

  it("reports no traffic variance without delay", () => {
    const free = scoreRoute(route([step(5000, 65, "DEPART"), step(2000, 25, "TURN_LEFT")]));
    expect(free.breakdown.traffic).toBe(0);
  });

  it("does not call a slow local route a high-speed environment", () => {
    for (const fixture of [urbanRoute, turnClusterRoute]) {
      expect(scoreRoute(fixture).reasons).not.toContain("High-speed environment");
    }
    expect(scoreRoute(turnClusterRoute).reasons).not.toContain("Mostly highway");
  });

  it("reports contributions that are the points actually scored", () => {
    for (const fixture of [highwayRoute, urbanRoute, trafficHeavyRoute, mergeClusterRoute]) {
      const result = scoreRoute(fixture);
      const points = result.contributions.reduce((sum, c) => sum + c.contribution, 0) * 10;
      // Below the 10-point cap the contributions sum to the raw score.
      if (result.uncalibratedScore! < 9.9) {
        expect(points).toBeCloseTo(result.uncalibratedScore!, 0);
      }
      const shares = result.contributions.map((c) => c.contribution);
      expect([...shares].sort((a, b) => b - a)).toEqual(shares);
      for (const c of result.contributions) {
        expect(Number.isFinite(c.weight)).toBe(true);
        expect(c.contribution).toBeGreaterThanOrEqual(0);
      }
    }
    expect(scoreRoute(trafficHeavyRoute).contributions.map((c) => c.factor)).toContain("traffic");
    expect(scoreRoute(mergeClusterRoute).contributions[0].factor).toBe("merges");
  });

  it("has no cliff at the old 65% highway / 45 minute discount gates", () => {
    const build = (highwayMeters: number) =>
      route([
        step(300, 30, "DEPART"),
        step(highwayMeters, 65, "MERGE"),
        step(20000 - highwayMeters, 30, "RAMP_RIGHT"),
      ]);
    let previous = scoreRoute(build(10000)).uncalibratedScore!;
    for (let meters = 10500; meters <= 16000; meters += 500) {
      const current = scoreRoute(build(meters)).uncalibratedScore!;
      expect(Math.abs(current - previous)).toBeLessThanOrEqual(0.4);
      previous = current;
    }
  });
});
