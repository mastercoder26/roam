import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchOsmRouteData } from "../osm.js";
import type { ParsedRoute } from "../../types.js";

const leftTurnRoute: ParsedRoute = {
  distanceMeters: 100,
  durationSeconds: 60,
  staticDurationSeconds: 50,
  polyline: "??_ibE?",
  bounds: {
    southwest: { lat: 0, lng: 0 },
    northeast: { lat: 0, lng: 1 },
  },
  steps: [{
    distanceMeters: 100,
    staticDurationSeconds: 50,
    maneuver: "TURN_LEFT",
    polyline: "??_ibE?",
  }],
};

const road = {
  type: "way",
  id: 1,
  tags: { highway: "residential" },
  geometry: [{ lat: 0, lon: 0 }, { lat: 0, lon: 1 }],
};

function mockOverpass(elements: unknown[]) {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ elements }), {
    status: 200,
  })));
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("OSM turn protection", () => {
  it("does not treat a stop sign as protected turn control", async () => {
    mockOverpass([road, {
      type: "node", id: 2, lat: 0, lon: 0, tags: { highway: "stop" },
    }]);

    const result = await fetchOsmRouteData(leftTurnRoute);

    expect(result.road.available).toBe(true);
    expect(result.turns).toMatchObject({
      available: false,
      unprotectedLeftTurns: 0,
      protectedLeftTurns: 0,
    });
  });

  it("marks ambiguous or distant traffic signals unavailable", async () => {
    mockOverpass([road,
      { type: "node", id: 2, lat: 0, lon: 0, tags: { highway: "traffic_signals" } },
      { type: "node", id: 3, lat: 0, lon: 0.0001, tags: { highway: "traffic_signals" } },
    ]);

    await expect(fetchOsmRouteData(leftTurnRoute)).resolves.toMatchObject({
      turns: { available: false },
    });
  });

  it("uses one nearby traffic signal as a protected-turn match", async () => {
    mockOverpass([road, {
      type: "node", id: 2, lat: 0, lon: 0, tags: { highway: "traffic_signals" },
    }]);

    await expect(fetchOsmRouteData(leftTurnRoute)).resolves.toMatchObject({
      turns: {
        available: true,
        unprotectedLeftTurns: 0,
        protectedLeftTurns: 1,
      },
    });
  });
});
