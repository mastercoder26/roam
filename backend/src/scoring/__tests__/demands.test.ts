import { describe, expect, it } from "vitest";
import { ROUTE_DEMAND_IDS, type RouteDemand } from "../../types.js";
import { neutralConditions, type RouteConditions } from "../../enrichment/types.js";
import { scoreRoute } from "../index.js";
import { highwayRoute } from "./fixtures/highway-route.js";
import { longDriveRoute } from "./fixtures/long-drive-route.js";
import { mergeClusterRoute } from "./fixtures/merge-cluster-route.js";
import { trafficHeavyRoute, trafficLightRoute } from "./fixtures/traffic-route.js";
import { urbanRoute } from "./fixtures/urban-route.js";

function routeDemand(
  result: ReturnType<typeof scoreRoute>,
  id: RouteDemand["id"]
): RouteDemand {
  const demand = result.routeDemands.find((item) => item.id === id);
  if (!demand) throw new Error(`Missing ${id} demand`);
  return demand;
}

describe("route demands", () => {
  it("always returns the complete, stable demand list", () => {
    const result = scoreRoute(highwayRoute);

    expect(result.routeDemands.map((item) => item.id)).toEqual(ROUTE_DEMAND_IDS);
    for (const item of result.routeDemands) {
      expect(item.intensity).toBeGreaterThanOrEqual(0);
      expect(item.intensity).toBeLessThanOrEqual(1);
      expect(["low", "moderate", "high"]).toContain(item.level);
      expect(item.evidence.length).toBeGreaterThan(0);
    }
  });

  it("uses the client-local clock instead of the timestamp's UTC hour", () => {
    const daytime = scoreRoute(longDriveRoute, {
      departureTime: "2026-06-06T03:00:00.000Z",
      departureLocalMinutes: 13 * 60,
    });
    const nighttime = scoreRoute(longDriveRoute, {
      departureTime: "2026-06-06T03:00:00.000Z",
      departureLocalMinutes: 22 * 60,
    });

    expect(routeDemand(daytime, "afterDark").intensity).toBe(0);
    expect(routeDemand(nighttime, "afterDark")).toMatchObject({
      available: true,
      intensity: 1,
      level: "high",
    });
    expect(nighttime.breakdown.fatigue).toBeGreaterThan(
      daytime.breakdown.fatigue
    );
  });

  it("tracks a route's progress into the after-dark window", () => {
    const result = scoreRoute(longDriveRoute, {
      departureLocalMinutes: 19 * 60 + 30,
    });

    expect(routeDemand(result, "afterDark").intensity).toBeCloseTo(0.83, 2);
  });

  it("makes fast-road, merge, and intersection demands factual", () => {
    const highway = scoreRoute(highwayRoute);
    const mergeCluster = scoreRoute(mergeClusterRoute);
    const urban = scoreRoute(urbanRoute);

    expect(routeDemand(highway, "fastRoads")).toMatchObject({
      available: true,
      level: "high",
    });
    expect(routeDemand(mergeCluster, "merges").intensity).toBeGreaterThan(0.4);
    expect(routeDemand(mergeCluster, "merges").evidence).toContain("merge");
    expect(routeDemand(urban, "complexIntersections").intensity).toBeGreaterThan(
      0.6
    );
  });

  it("keeps unsupported weather and road data unavailable", () => {
    const result = scoreRoute(highwayRoute, {
      conditions: neutralConditions(),
    });

    expect(routeDemand(result, "weatherVisibility")).toMatchObject({
      available: false,
      intensity: 0,
    });
    expect(routeDemand(result, "roadConditions")).toMatchObject({
      available: false,
      intensity: 0,
    });
  });

  it("requires a successful source before exposing weather or road conditions", () => {
    const base = neutralConditions();
    const unverified: RouteConditions = {
      ...base,
      weather: {
        ...base.weather,
        available: true,
        condition: "Rain",
        severity: 0.9,
      },
      road: {
        ...base.road,
        available: true,
        constructionZones: 3,
      },
      sources: [],
    };
    const result = scoreRoute(highwayRoute, { conditions: unverified });

    expect(routeDemand(result, "weatherVisibility").available).toBe(false);
    expect(routeDemand(result, "roadConditions").available).toBe(false);
  });

  it("uses only available weather and road sources in their demands", () => {
    const base = neutralConditions();
    const conditions: RouteConditions = {
      ...base,
      weather: {
        ...base.weather,
        available: true,
        condition: "Rain",
        severity: 0.8,
        lowVisibilityRisk: 0.6,
        visibilityMiles: 2.5,
      },
      road: {
        ...base.road,
        available: true,
        constructionZones: 2,
        narrowRoadShare: 0.25,
      },
      sources: ["open-meteo", "osm-overpass"],
    };
    const result = scoreRoute(highwayRoute, { conditions });

    expect(routeDemand(result, "weatherVisibility")).toMatchObject({
      available: true,
      level: "high",
    });
    expect(routeDemand(result, "weatherVisibility").evidence).toContain("Rain");
    expect(routeDemand(result, "roadConditions")).toMatchObject({
      available: true,
      level: "moderate",
    });
  });

  it("reports traffic from traffic-aware duration without inventing road data", () => {
    const light = scoreRoute(trafficLightRoute);
    const heavy = scoreRoute(trafficHeavyRoute);

    expect(routeDemand(heavy, "traffic").intensity).toBeGreaterThan(
      routeDemand(light, "traffic").intensity
    );
    expect(routeDemand(heavy, "traffic").evidence).toContain("longer");
    expect(routeDemand(heavy, "roadConditions").available).toBe(false);
  });
});
