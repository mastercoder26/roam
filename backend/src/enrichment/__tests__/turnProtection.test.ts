import { describe, expect, it } from "vitest";
import { determineTurnProtection } from "../turnProtection.js";

describe("turn protection confidence", () => {
  const turn = { lat: 0, lng: 0 };

  it("marks routes without left turns as available with no exposure", () => {
    expect(determineTurnProtection([], [])).toMatchObject({
      available: true,
      protectedLeftTurns: 0,
      unprotectedLeftTurns: 0,
    });
  });

  it("does not infer protection from stop controls, distant signals, or ambiguous signals", () => {
    for (const nodes of [
      [{ lat: 0, lon: 0, tags: { highway: "stop" } }],
      [{ lat: 0, lon: 0.001, tags: { highway: "traffic_signals" } }],
      [
        { lat: 0, lon: 0, tags: { highway: "traffic_signals" } },
        { lat: 0, lon: 0.0001, tags: { highway: "traffic_signals" } },
      ],
    ]) {
      expect(determineTurnProtection([turn], nodes)).toMatchObject({
        available: false,
        protectedLeftTurns: 0,
        unprotectedLeftTurns: 0,
      });
    }
  });

  it("requires one nearby traffic signal at every turn", () => {
    expect(determineTurnProtection(
      [turn, { lat: 0, lng: 0.01 }],
      [
        { lat: 0, lon: 0, tags: { highway: "traffic_signals" } },
        { lat: 0, lon: 0.01, tags: { highway: "traffic_signals" } },
      ]
    )).toEqual({
      available: true,
      protectedLeftTurns: 2,
      unprotectedLeftTurns: 0,
      unprotectedTurnShare: 0,
    });
  });
});
