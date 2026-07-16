import type { ParsedRoute } from "../types.js";
import type { RouteConditions } from "../enrichment/types.js";
import { smoothstep } from "./helpers.js";
import {
  computeHighwayShare,
  isHighwayStep,
  computeManeuverComplexity,
  computeMergeBurden,
  computeTurnClustering,
} from "./signals.js";
import {
  aggregateSegmentScores,
  segmentRoute,
  type RouteSegment,
  type SegmentAggregateResult,
} from "./segments.js";

export interface RouteFeatures {
  meanSpeedMph: number;
  maxSpeedMph: number;
  fractionAbove45Mph: number;
  fractionAbove60Mph: number;
  durationMinutes: number;
  durationHours: number;
  distanceMiles: number;
  stepCount: number;
  turnDensity: number;
  leftTurnCount: number;
  rampCount: number;
  mergeCount: number;
  interchangeDensity: number;
  exponentialSpacing: number;
  mergeClusterCount: number;
  weaveCount: number;
  weaveSectionScore: number;
  mergeBurdenSubscore: number;
  trafficRatio: number;
  trafficVariance: number;
  nighttimeShare: number;
  urbanShare: number;
  highwayShare: number;
  longestHighwaySegmentMiles: number;
  monotonyScore: number;
  decisionPointDensity: number;
  segmentP90Difficulty: number;
  segmentMaxDifficulty: number;
  segmentMeanDifficulty: number;
  segmentAggregated: number;
  laneChangeUrgency: number;
  turnClusterCount: number;
  closeTurnPairs: number;
  turnSpacingPressure: number;
  turnClusterSubscore: number;
  sharpTurnCount: number;
  maneuversPer10Mi: number;
  stepsPerMile: number;
  delayRatio: number;
  /** 0–1 combined weather severity at drive time (rain, snow, wind, fog, ice). */
  weatherSeverity: number;
  precipIntensity: number;
  snowRisk: number;
  windSeverity: number;
  lowVisibilityRisk: number;
  icyRisk: number;
  /** 0–1: how much of the route runs on small/narrow roads (higher = harder). */
  roadSizeScore: number;
  narrowRoadShare: number;
  majorRoadShare: number;
  unpavedShare: number;
  avgLanes: number;
  constructionZones: number;
  /** 0–1 normalized construction burden. */
  constructionSeverity: number;
  /** Left turns without signal/stop protection (crossing oncoming traffic). */
  unprotectedLeftTurns: number;
  /** 0–1 share of left turns that are unprotected. */
  unprotectedTurnShare: number;
}

export interface BuildFeaturesInput {
  route: ParsedRoute;
  segments: RouteSegment[];
  stepSpeedsMph?: Map<number, number>;
  departureTime?: string;
  /** Local clock minutes supplied by the client (0 = midnight). */
  departureLocalMinutes?: number;
  conditions?: RouteConditions;
}

export function isValidDepartureLocalMinutes(
  value: unknown
): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 0 &&
    value < 24 * 60
  );
}

/**
 * Resolve a client-local clock for route timing. New clients always supply
 * `departureLocalMinutes`; the timestamp path is retained only so older
 * clients keep a deterministic, host-timezone-independent fallback.
 */
export function resolveDepartureLocalMinutes(
  departureLocalMinutes?: number,
  departureTime?: string
): number | undefined {
  if (isValidDepartureLocalMinutes(departureLocalMinutes)) {
    return departureLocalMinutes;
  }

  if (!departureTime) return undefined;
  const legacyDeparture = new Date(departureTime);
  if (Number.isNaN(legacyDeparture.getTime())) return undefined;

  return (
    legacyDeparture.getUTCHours() * 60 + legacyDeparture.getUTCMinutes()
  );
}

function isNightLocalMinute(localMinutes: number): boolean {
  const hour = Math.floor(localMinutes / 60);
  return hour >= 20 || hour < 6;
}

/** Exact overlap with the repeating 8 PM–6 AM local-time window. */
function nighttimeSecondsInInterval(
  startLocalMinutes: number,
  durationSeconds: number
): number {
  let remainingSeconds = Math.max(0, durationSeconds);
  let cursorMinutes = startLocalMinutes % (24 * 60);
  let nighttimeSeconds = 0;

  while (remainingSeconds > 0.001) {
    const nighttime = isNightLocalMinute(cursorMinutes);
    const hour = Math.floor(cursorMinutes / 60);
    const boundaryMinutes = nighttime
      ? hour < 6
        ? 6 * 60
        : 24 * 60
      : 20 * 60;
    const secondsUntilBoundary = Math.max(
      0.001,
      (boundaryMinutes - cursorMinutes) * 60
    );
    const spanSeconds = Math.min(remainingSeconds, secondsUntilBoundary);

    if (nighttime) nighttimeSeconds += spanSeconds;
    remainingSeconds -= spanSeconds;
    cursorMinutes = (cursorMinutes + spanSeconds / 60) % (24 * 60);
  }

  return nighttimeSeconds;
}

function computeSpeedStats(
  route: ParsedRoute,
  stepSpeedsMph?: Map<number, number>
): Pick<
  RouteFeatures,
  "meanSpeedMph" | "maxSpeedMph" | "fractionAbove45Mph" | "fractionAbove60Mph"
> {
  let totalMeters = 0;
  let weightedSpeed = 0;
  let maxSpeed = 0;
  let above45 = 0;
  let above60 = 0;

  route.steps.forEach((step, i) => {
    const dist = step.distanceMeters;
    if (dist <= 0) return;
    totalMeters += dist;

    let speed =
      stepSpeedsMph?.get(i) ??
      (step.staticDurationSeconds > 0
        ? (dist / 1609.34) / (step.staticDurationSeconds / 3600)
        : 0);

    weightedSpeed += speed * dist;
    maxSpeed = Math.max(maxSpeed, speed);
    if (speed >= 45) above45 += dist;
    if (speed >= 60) above60 += dist;
  });

  const meanSpeedMph = totalMeters > 0 ? weightedSpeed / totalMeters : 0;
  return {
    meanSpeedMph,
    maxSpeedMph: maxSpeed,
    fractionAbove45Mph: totalMeters > 0 ? above45 / totalMeters : 0,
    fractionAbove60Mph: totalMeters > 0 ? above60 / totalMeters : 0,
  };
}

function longestHighwayRunMiles(
  route: ParsedRoute,
  stepSpeedsMph?: Map<number, number>
): number {
  let longest = 0;
  let current = 0;
  route.steps.forEach((step, i) => {
    if (isHighwayStep(step, stepSpeedsMph?.get(i))) {
      current += step.distanceMeters / 1609.34;
      longest = Math.max(longest, current);
    } else {
      current = 0;
    }
  });
  return longest;
}

function computeNighttimeShare(
  segments: RouteSegment[],
  departureLocalMinutes?: number,
  departureTime?: string
): number {
  if (segments.length === 0) return 0;
  const startLocalMinutes = resolveDepartureLocalMinutes(
    departureLocalMinutes,
    departureTime
  );
  if (startLocalMinutes === undefined) return 0;

  let nightSeconds = 0;
  let totalSeconds = 0;
  for (const seg of segments) {
    totalSeconds += seg.durationSeconds;
    nightSeconds += nighttimeSecondsInInterval(
      startLocalMinutes + seg.cumulativeSecondsFromStart / 60,
      seg.durationSeconds
    );
  }
  return totalSeconds > 0 ? nightSeconds / totalSeconds : 0;
}

function computeDecisionPointDensity(segments: RouteSegment[]): number {
  const windowSeconds = 300;
  let maxDensity = 0;

  for (const seg of segments) {
    const windowStart = seg.cumulativeSecondsFromStart;
    const windowEnd = windowStart + windowSeconds;
    let decisions = 0;
    let miles = 0;

    for (const other of segments) {
      const segMid = other.cumulativeSecondsFromStart + other.durationSeconds / 2;
      if (segMid >= windowStart && segMid <= windowEnd) {
        decisions += other.maneuvers.length;
        miles += other.distanceMeters / 1609.34;
      }
    }
    if (miles > 0) {
      maxDensity = Math.max(maxDensity, decisions / miles);
    }
  }
  return maxDensity;
}

function computeMonotony(
  highwayShare: number,
  longestHighwaySegmentMiles: number,
  durationHours: number
): number {
  if (highwayShare < 0.5) return 0;
  return Math.min(
    1,
    (longestHighwaySegmentMiles / 40) * 0.5 + (durationHours / 4) * 0.5
  );
}

function computeLaneChangeUrgency(segments: RouteSegment[]): number {
  let urgency = 0;
  for (const seg of segments) {
    const mergeLike = seg.maneuvers.filter(
      (m) => m === "MERGE" || m.startsWith("RAMP_") || m.startsWith("FORK_")
    ).length;
    if (mergeLike >= 2) urgency += 0.25;
    else if (mergeLike === 1 && seg.impliedSpeedMph >= 55) urgency += 0.15;
  }
  return Math.min(1, urgency / Math.max(1, segments.length * 0.08));
}

interface ConditionFeatures {
  weatherSeverity: number;
  precipIntensity: number;
  snowRisk: number;
  windSeverity: number;
  lowVisibilityRisk: number;
  icyRisk: number;
  roadSizeScore: number;
  narrowRoadShare: number;
  majorRoadShare: number;
  unpavedShare: number;
  avgLanes: number;
  constructionZones: number;
  constructionSeverity: number;
  unprotectedLeftTurns: number;
  unprotectedTurnShare: number;
}

function deriveConditionFeatures(
  leftTurnCount: number,
  conditions?: RouteConditions
): ConditionFeatures {
  const weather = conditions?.weather;
  const road = conditions?.road;
  const turns = conditions?.turns;

  // Without intersection-control data, stay neutral (0) so missing OSM does
  // not invent difficulty. Left-turn count still feeds the turn component.
  const unprotectedLeftTurns = turns?.available ? turns.unprotectedLeftTurns : 0;
  const unprotectedTurnShare = turns?.available ? turns.unprotectedTurnShare : 0;

  const constructionZones = road?.constructionZones ?? 0;

  return {
    weatherSeverity: weather?.available ? weather.severity : 0,
    precipIntensity: weather?.precipIntensity ?? 0,
    snowRisk: weather?.snowRisk ?? 0,
    windSeverity: weather?.windSeverity ?? 0,
    lowVisibilityRisk: weather?.lowVisibilityRisk ?? 0,
    icyRisk: weather?.icyRisk ?? 0,
    roadSizeScore: road?.available ? road.roadSizeScore : 0,
    narrowRoadShare: road?.narrowRoadShare ?? 0,
    majorRoadShare: road?.majorRoadShare ?? 0,
    unpavedShare: road?.unpavedShare ?? 0,
    avgLanes: road?.avgLanes ?? 0,
    constructionZones,
    constructionSeverity: smoothstep(constructionZones / 4),
    unprotectedLeftTurns,
    unprotectedTurnShare,
  };
}

export function buildFeatures(input: BuildFeaturesInput): RouteFeatures {
  const {
    route,
    segments,
    stepSpeedsMph,
    departureTime,
    departureLocalMinutes,
    conditions,
  } = input;
  const speedStats = computeSpeedStats(route, stepSpeedsMph);
  const { highwayShare } = computeHighwayShare(route.steps, stepSpeedsMph);
  const maneuvers = computeManeuverComplexity(route.steps, route.distanceMeters);
  const trafficRatio =
    route.staticDurationSeconds > 0
      ? route.durationSeconds / route.staticDurationSeconds
      : 1;
  const delayRatio = Math.max(0, trafficRatio - 1);
  const merge = computeMergeBurden(route.steps, route.distanceMeters, trafficRatio);
  const turnCluster = computeTurnClustering(route.steps, route.distanceMeters);
  const segmentAgg: SegmentAggregateResult = aggregateSegmentScores(segments);

  let leftTurnCount = 0;
  for (const step of route.steps) {
    const m = step.maneuver ?? "";
    if (m.includes("LEFT") && m.startsWith("TURN")) leftTurnCount++;
  }

  const distanceMiles = route.distanceMeters / 1609.34;
  // Prefer traffic-aware duration for length/effort; fall back to static.
  const durationSeconds =
    route.durationSeconds > 0 ? route.durationSeconds : route.staticDurationSeconds;
  const durationHours = durationSeconds / 3600;
  const longestHighwaySegmentMiles = longestHighwayRunMiles(route, stepSpeedsMph);
  const urbanShare = 1 - highwayShare;
  const stepsPerMile = distanceMiles > 0 ? route.steps.length / distanceMiles : 0;
  const turnDensity = distanceMiles > 0 ? maneuvers.weightedCount / distanceMiles : 0;

  const segmentSpeedRatios = segments.map((s) =>
    s.durationSeconds > 0 ? s.impliedSpeedMph / 55 : 1
  );
  const meanSpeedRatio =
    segmentSpeedRatios.reduce((a, b) => a + b, 0) / Math.max(1, segmentSpeedRatios.length);
  const trafficVariance = Math.min(
    1,
    segmentSpeedRatios.reduce((acc, r) => acc + Math.abs(r - meanSpeedRatio), 0) /
      Math.max(1, segmentSpeedRatios.length)
  );

  return {
    ...speedStats,
    durationMinutes: durationSeconds / 60,
    durationHours,
    distanceMiles,
    stepCount: route.steps.length,
    turnDensity,
    leftTurnCount,
    rampCount: merge.rampCount,
    mergeCount: merge.mergeCount,
    interchangeDensity: merge.interchangeDensity,
    exponentialSpacing: merge.exponentialSpacing,
    mergeClusterCount: merge.mergeClusterCount,
    weaveCount: merge.weaveCount,
    weaveSectionScore: merge.weaveSectionScore,
    mergeBurdenSubscore: merge.subscore,
    trafficRatio,
    trafficVariance: trafficVariance * (1 + delayRatio),
    nighttimeShare: computeNighttimeShare(
      segments,
      departureLocalMinutes,
      departureTime
    ),
    urbanShare,
    highwayShare,
    longestHighwaySegmentMiles,
    monotonyScore: computeMonotony(highwayShare, longestHighwaySegmentMiles, durationHours),
    decisionPointDensity: computeDecisionPointDensity(segments),
    segmentP90Difficulty: segmentAgg.p90,
    segmentMaxDifficulty: segmentAgg.max,
    segmentMeanDifficulty: segmentAgg.mean,
    segmentAggregated: segmentAgg.aggregated,
    laneChangeUrgency: computeLaneChangeUrgency(segments),
    turnClusterCount: turnCluster.turnClusterCount,
    closeTurnPairs: turnCluster.closeTurnPairs,
    turnSpacingPressure: turnCluster.turnSpacingPressure,
    turnClusterSubscore: turnCluster.subscore,
    sharpTurnCount: turnCluster.sharpTurnCount,
    maneuversPer10Mi: maneuvers.maneuversPer10Mi,
    stepsPerMile,
    delayRatio,
    ...deriveConditionFeatures(leftTurnCount, conditions),
  };
}


export function buildFeaturesFromRoute(
  route: ParsedRoute,
  options: {
    stepSpeedsMph?: Map<number, number>;
    departureTime?: string;
    departureLocalMinutes?: number;
    conditions?: RouteConditions;
  } = {}
): { segments: RouteSegment[]; features: RouteFeatures } {
  const segments = segmentRoute(route, options.stepSpeedsMph);
  const features = buildFeatures({
    route,
    segments,
    stepSpeedsMph: options.stepSpeedsMph,
    departureTime: options.departureTime,
    departureLocalMinutes: options.departureLocalMinutes,
    conditions: options.conditions,
  });
  return { segments, features };
}
