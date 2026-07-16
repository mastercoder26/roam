import type {
  ParsedRoute,
  RouteDemand,
  RouteDemandId,
} from "../types.js";
import type { RouteConditions } from "../enrichment/types.js";
import {
  resolveDepartureLocalMinutes,
  type RouteFeatures,
} from "./features.js";

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function roundedIntensity(value: number): number {
  return Math.round(clamp01(value) * 100) / 100;
}

function levelFor(intensity: number): RouteDemand["level"] {
  if (intensity >= 0.67) return "high";
  if (intensity >= 0.34) return "moderate";
  return "low";
}

function demand(
  id: RouteDemandId,
  title: string,
  intensity: number,
  evidence: string,
  available: boolean
): RouteDemand {
  const normalized = available ? roundedIntensity(intensity) : 0;
  return {
    id,
    title,
    intensity: normalized,
    level: levelFor(normalized),
    evidence,
    available,
  };
}

function percent(value: number): string {
  return `${Math.round(clamp01(value) * 100)}%`;
}

function whole(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}

function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${whole(count)} ${Math.abs(count - 1) < 0.01 ? singular : pluralForm}`;
}

function hasRouteSteps(route: ParsedRoute): boolean {
  return route.steps.some((step) => step.distanceMeters > 0);
}

function intersectionInstructionCount(route: ParsedRoute): number {
  return route.steps.filter((step) => {
    const maneuver = step.maneuver ?? "";
    return (
      maneuver.startsWith("TURN_") ||
      maneuver.startsWith("FORK_") ||
      maneuver.startsWith("ROUNDABOUT_") ||
      maneuver.startsWith("UTURN_")
    );
  }).length;
}

function afterDarkDemand(
  features: RouteFeatures,
  departureLocalMinutes?: number,
  departureTime?: string
): RouteDemand {
  const localMinutes = resolveDepartureLocalMinutes(
    departureLocalMinutes,
    departureTime
  );
  if (localMinutes === undefined) {
    return demand(
      "afterDark",
      "After-dark driving",
      0,
      "Set a departure time to measure after-dark driving.",
      false
    );
  }

  const intensity = features.nighttimeShare;
  const startHour = Math.floor(localMinutes / 60);
  if (intensity <= 0.01) {
    return demand(
      "afterDark",
      "After-dark driving",
      intensity,
      `The ${startHour === 0 ? "midnight" : "scheduled"} departure keeps this drive outside the 8 PM–6 AM window.`,
      true
    );
  }

  const period = intensity >= 0.99 ? "The full drive" : `About ${percent(intensity)} of the drive`;
  return demand(
    "afterDark",
    "After-dark driving",
    intensity,
    `${period} falls in the 8 PM–6 AM window.`,
    true
  );
}

function fastRoadsDemand(
  route: ParsedRoute,
  features: RouteFeatures
): RouteDemand {
  const available = hasRouteSteps(route);
  if (!available) {
    return demand(
      "fastRoads",
      "Fast roads",
      0,
      "Route speed information was unavailable.",
      false
    );
  }

  const intensity =
    features.fractionAbove45Mph * 0.55 + features.fractionAbove60Mph * 0.45;
  if (features.fractionAbove45Mph <= 0.01) {
    return demand(
      "fastRoads",
      "Fast roads",
      intensity,
      "No route segments are estimated at 45 mph or faster.",
      true
    );
  }

  const sixtyPlus =
    features.fractionAbove60Mph > 0.01
      ? `, including ${percent(features.fractionAbove60Mph)} at 60+ mph`
      : "";
  return demand(
    "fastRoads",
    "Fast roads",
    intensity,
    `${percent(features.fractionAbove45Mph)} of the route is estimated at 45+ mph${sixtyPlus}.`,
    true
  );
}

function mergesDemand(
  route: ParsedRoute,
  features: RouteFeatures
): RouteDemand {
  const available = hasRouteSteps(route);
  if (!available) {
    return demand(
      "merges",
      "Merges and ramps",
      0,
      "Route maneuver information was unavailable.",
      false
    );
  }

  const transitions = features.mergeCount + features.rampCount;
  const intensity =
    features.mergeBurdenSubscore * 0.55 +
    Math.min(1, transitions / 4) * 0.25 +
    Math.min(1, features.weaveCount / 3) * 0.12 +
    Math.min(1, features.mergeClusterCount / 2) * 0.08;

  if (transitions === 0) {
    return demand(
      "merges",
      "Merges and ramps",
      intensity,
      "No ramps or merges were detected in the route instructions.",
      true
    );
  }

  const clusterDetail =
    features.mergeClusterCount > 0
      ? `, including ${plural(features.mergeClusterCount, "tight cluster")}`
      : "";
  const weaveDetail =
    features.weaveCount > 0
      ? ` and ${plural(features.weaveCount, "weave section")}`
      : "";
  return demand(
    "merges",
    "Merges and ramps",
    intensity,
    `${plural(transitions, "ramp or merge transition", "ramps or merge transitions")} appear in the route instructions${clusterDetail}${weaveDetail}.`,
    true
  );
}

function complexIntersectionsDemand(
  route: ParsedRoute,
  features: RouteFeatures,
  conditions?: RouteConditions
): RouteDemand {
  const available = hasRouteSteps(route);
  if (!available) {
    return demand(
      "complexIntersections",
      "Complex intersections",
      0,
      "Route maneuver information was unavailable.",
      false
    );
  }

  const intersections = intersectionInstructionCount(route);
  const structuralIntensity = Math.max(
    features.turnClusterSubscore,
    clamp01(features.maneuversPer10Mi / 12),
    clamp01(features.decisionPointDensity / 8)
  );
  const turns = conditions?.turns;
  const verifiedIntersectionControls = Boolean(
    turns?.available && conditions?.sources.includes("osm-overpass")
  );
  const protectedTurnIntensity = verifiedIntersectionControls && turns
    ? turns.unprotectedTurnShare * 0.25 +
      clamp01(turns.unprotectedLeftTurns / 6) * 0.2
    : 0;
  const intensity = Math.max(structuralIntensity, protectedTurnIntensity);

  if (intersections === 0) {
    return demand(
      "complexIntersections",
      "Complex intersections",
      intensity,
      "No turn, fork, roundabout, or U-turn instructions were detected.",
      true
    );
  }

  const clusterDetail =
    features.turnClusterCount > 0
      ? ` ${plural(features.turnClusterCount, "turn cluster")} contains closely spaced decisions.`
      : "";
  const unprotectedDetail =
    verifiedIntersectionControls && turns && turns.unprotectedLeftTurns > 0
      ? ` ${plural(turns.unprotectedLeftTurns, "unprotected left turn")} was identified from available intersection data.`
      : "";
  return demand(
    "complexIntersections",
    "Complex intersections",
    intensity,
    `${plural(intersections, "turn, fork, roundabout, or U-turn instruction", "turn, fork, roundabout, or U-turn instructions")} appear on this route.${clusterDetail}${unprotectedDetail}`,
    true
  );
}

function weatherVisibilityDemand(conditions?: RouteConditions): RouteDemand {
  const weather = conditions?.weather;
  const available = Boolean(
    weather?.available && conditions?.sources.includes("open-meteo")
  );
  if (!available || !weather) {
    return demand(
      "weatherVisibility",
      "Weather and visibility",
      0,
      "Live weather and visibility data were unavailable, so they are not included.",
      false
    );
  }

  const intensity = Math.max(
    weather.severity,
    weather.lowVisibilityRisk,
    weather.windSeverity * 0.75,
    weather.snowRisk,
    weather.icyRisk
  );
  const details = [weather.condition];
  if (weather.visibilityMiles > 0 && weather.visibilityMiles < 10) {
    details.push(`${weather.visibilityMiles.toFixed(1)} mi visibility`);
  }
  if (weather.windGustMph >= 25) {
    details.push(`${whole(weather.windGustMph)} mph gusts`);
  }
  return demand(
    "weatherVisibility",
    "Weather and visibility",
    intensity,
    `Live route weather: ${details.join("; ")}.`,
    true
  );
}

function sustainedDriveDemand(
  route: ParsedRoute,
  features: RouteFeatures
): RouteDemand {
  const available = route.durationSeconds > 0 || route.staticDurationSeconds > 0;
  if (!available) {
    return demand(
      "sustainedDrive",
      "Sustained drive",
      0,
      "Route duration was unavailable.",
      false
    );
  }

  const intensity = clamp01((features.durationMinutes - 10) / 170);
  return demand(
    "sustainedDrive",
    "Sustained drive",
    intensity,
    `Expected drive time is about ${whole(features.durationMinutes)} minutes.`,
    true
  );
}

function trafficDemand(route: ParsedRoute, features: RouteFeatures): RouteDemand {
  const available =
    route.durationSeconds > 0 && route.staticDurationSeconds > 0;
  if (!available) {
    return demand(
      "traffic",
      "Traffic",
      0,
      "Traffic-aware route timing was unavailable.",
      false
    );
  }

  const delaySeconds = Math.max(
    0,
    route.durationSeconds - route.staticDurationSeconds
  );
  const intensity = Math.max(
    clamp01(features.delayRatio / 0.45),
    clamp01(features.trafficVariance * 0.65)
  );
  if (delaySeconds < 60) {
    return demand(
      "traffic",
      "Traffic",
      intensity,
      "Traffic-aware timing is close to the route's no-traffic estimate.",
      true
    );
  }

  return demand(
    "traffic",
    "Traffic",
    intensity,
    `Traffic-aware timing is ${whole(delaySeconds / 60)} minutes (${percent(features.delayRatio)}) longer than the no-traffic estimate.`,
    true
  );
}

function roadConditionsDemand(conditions?: RouteConditions): RouteDemand {
  const road = conditions?.road;
  const osmRoadDataAvailable = Boolean(
    road?.available && conditions?.sources.includes("osm-overpass")
  );
  const routeWarningsSupportConstruction = Boolean(
    conditions?.sources.includes("google-route-warnings") &&
      road &&
      road.constructionZones > 0
  );
  const available = osmRoadDataAvailable || routeWarningsSupportConstruction;
  if (!available || !road) {
    return demand(
      "roadConditions",
      "Road conditions",
      0,
      "Road-surface and construction data were unavailable, so they are not included.",
      false
    );
  }

  const intensity = Math.max(
    road.roadSizeScore,
    road.narrowRoadShare,
    road.unpavedShare,
    clamp01(road.constructionZones / 4)
  );

  if (!osmRoadDataAvailable && routeWarningsSupportConstruction) {
    return demand(
      "roadConditions",
      "Road conditions",
      intensity,
      "The route provider reports construction or roadwork along this route.",
      true
    );
  }

  const details: string[] = [];
  if (road.constructionZones > 0) {
    details.push(`${plural(road.constructionZones, "reported construction zone")}`);
  }
  if (road.narrowRoadShare > 0.05) {
    details.push(`${percent(road.narrowRoadShare)} on smaller roads`);
  }
  if (road.unpavedShare > 0.05) {
    details.push(`${percent(road.unpavedShare)} unpaved`);
  }
  if (details.length === 0) {
    details.push("no notable narrow-road, unpaved, or construction exposure detected");
  }
  return demand(
    "roadConditions",
    "Road conditions",
    intensity,
    `Road data shows ${details.join("; ")}.`,
    true
  );
}

export interface BuildRouteDemandsOptions {
  departureTime?: string;
  departureLocalMinutes?: number;
  conditions?: RouteConditions;
}

/**
 * Build all demand categories in a fixed order so mobile clients can decode a
 * complete, stable readiness input even when live enrichment is unavailable.
 */
export function buildRouteDemands(
  route: ParsedRoute,
  features: RouteFeatures,
  options: BuildRouteDemandsOptions = {}
): RouteDemand[] {
  return [
    afterDarkDemand(
      features,
      options.departureLocalMinutes,
      options.departureTime
    ),
    fastRoadsDemand(route, features),
    mergesDemand(route, features),
    complexIntersectionsDemand(route, features, options.conditions),
    weatherVisibilityDemand(options.conditions),
    sustainedDriveDemand(route, features),
    trafficDemand(route, features),
    roadConditionsDemand(options.conditions),
  ];
}
