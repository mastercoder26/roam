import { afterEach, describe, expect, it, vi } from "vitest";
import { computeRoutes } from "../routes.js";

const validRoute = {
  distanceMeters: 100,
  duration: "60s",
  staticDuration: "50s",
  polyline: { encodedPolyline: "??_ibE?" },
  viewport: {
    low: { latitude: 0, longitude: 0 },
    high: { latitude: 0, longitude: 1 },
  },
  legs: [{
    steps: [{
      distanceMeters: 100,
      staticDuration: "50s",
      navigationInstruction: { maneuver: "STRAIGHT", instructions: "Continue" },
    }],
  }],
};

const params = {
  origin: "A",
  destination: "B",
  apiKey: "test-key",
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("Google Routes payload validation", () => {
  it("parses a complete provider route", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      routes: [validRoute],
    }), { status: 200 })));

    await expect(computeRoutes(params)).resolves.toMatchObject([{
      distanceMeters: 100,
      durationSeconds: 60,
      staticDurationSeconds: 50,
      trafficTimingAvailable: true,
      polyline: "??_ibE?",
    }]);
  });

  it("sends recorded GPS endpoints as native Google location waypoints", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      routes: [validRoute],
    }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await computeRoutes({
      ...params,
      origin: { latitude: 30.2672, longitude: -97.7431 },
      destination: { latitude: 30.3072, longitude: -97.7031 },
    });

    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(request.origin).toEqual({
      location: { latLng: { latitude: 30.2672, longitude: -97.7431 } },
    });
    expect(request.destination).toEqual({
      location: { latLng: { latitude: 30.3072, longitude: -97.7031 } },
    });
  });

  it("accepts zero-length provider steps when another step is usable", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      routes: [{
        ...validRoute,
        legs: [{
          steps: [
            { distanceMeters: 0, staticDuration: "0s" },
            ...validRoute.legs[0].steps,
          ],
        }],
      }],
    }), { status: 200 })));

    await expect(computeRoutes(params)).resolves.toHaveLength(1);
  });

  it.each([
    ["missing overview geometry", { ...validRoute, polyline: undefined }],
    ["zero distance", { ...validRoute, distanceMeters: 0 }],
    ["invalid duration", { ...validRoute, duration: "soon" }],
    ["missing viewport", { ...validRoute, viewport: undefined }],
    ["missing steps", { ...validRoute, legs: [] }],
  ])("rejects a route with %s", async (_label, invalidRoute) => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({
      routes: [invalidRoute],
    }), { status: 200 })));

    await expect(computeRoutes(params)).rejects.toThrow("Routes provider returned invalid data");
  });

  it("normalizes provider transport and response failures", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));
    await expect(computeRoutes(params)).rejects.toThrow("Routes provider returned invalid data");

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("provider details", { status: 429 })));
    await expect(computeRoutes(params)).rejects.toThrow("Routes provider returned invalid data");

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("not json", { status: 200 })));
    await expect(computeRoutes({ ...params, departureTime: "2026-07-18T18:30:00-05:00" }))
      .rejects.toThrow("Routes provider returned invalid data");
  });
});
