import type { DriverContext } from "../types.js";
import { BASE_SCORE_WEIGHTS, type BaseScoreComponents } from "./baseScore.js";
import type { RouteFeatures } from "./features.js";
import { smoothstep, computeSustainedEffortFromHours } from "./helpers.js";

export interface FatigueResult {
  durationMinutes: number;
  circadianPenalty: number;
  continuousPenalty: number;
  D_fatigue: number;
  D_interaction: number;
}

/** Shared divisor for fatigueNorm / fatigueSubscore. */
export const FATIGUE_NORM_DIVISOR = 1.8;

/** Circadian + prior continuous driving (duration handled via durationPoints). */
export const FATIGUE_COEFFICIENTS = {
  a1: 0.28,
  a2: 0.4,
  a3: 0.32,
} as const;

/**
 * Trip-length burden independent of road complexity (0–1).
 */
export function durationBurden(hours: number): number {
  if (hours <= 0.2) return 0;
  return Math.min(
    1,
    smoothstep((hours - 0.2) / 3.3) * 0.8 + smoothstep((hours - 3.5) / 6) * 0.2
  );
}

/**
 * Primary duration contribution on the 0–10 scale.
 * Short hop ~0, 2h ~1.2, 4h ~2.8, 8h ~4.0.
 */
export function durationPoints(hours: number): number {
  return 2.8 * smoothstep(hours / 4.5) + 1.2 * smoothstep((hours - 4) / 6);
}

/**
 * Circadian alertness cost by local clock hour, as a continuous curve.
 * The previous step function jumped from 0.1 to 0.85 between 21:59 and 22:00
 * and from 1.0 to 0.4 between 05:59 and 06:00, so a one-minute change in
 * departure moved the score.
 */
const CIRCADIAN_KNOTS: ReadonlyArray<readonly [hour: number, penalty: number]> = [
  [0, 1.0],
  [5, 1.0],
  [6.5, 0.4],
  [8, 0.15],
  [10, 0.1],
  [14, 0.1],
  [15.5, 0.35],
  [17.5, 0.35],
  [19, 0.15],
  [21, 0.3],
  [22.5, 0.85],
  [24, 1.0],
];

export function circadianPenaltyAtHour(localHour: number): number {
  if (!Number.isFinite(localHour)) return 0;
  const hour = ((localHour % 24) + 24) % 24;
  for (let i = 1; i < CIRCADIAN_KNOTS.length; i++) {
    const [h1, p1] = CIRCADIAN_KNOTS[i];
    if (hour <= h1) {
      const [h0, p0] = CIRCADIAN_KNOTS[i - 1];
      return p0 + ((hour - h0) / (h1 - h0)) * (p1 - p0);
    }
  }
  return 1.0;
}

/**
 * Mean circadian cost over the whole drive, not just its first minute: a
 * 21:00 departure that runs until 02:00 is a night drive.
 *
 * Prefer the driver's local clock supplied by the client. The Date fallback is
 * only for older clients and intentionally uses UTC so server locale never
 * changes the result.
 */
function circadianPenalty(
  departureTime: Date | undefined,
  departureLocalMinutes: number | undefined,
  durationHours: number
): number {
  let startMinutes: number | undefined;
  if (
    typeof departureLocalMinutes === "number" &&
    Number.isInteger(departureLocalMinutes) &&
    departureLocalMinutes >= 0 &&
    departureLocalMinutes < 24 * 60
  ) {
    startMinutes = departureLocalMinutes;
  } else if (departureTime && Number.isFinite(departureTime.getTime())) {
    startMinutes = departureTime.getUTCHours() * 60 + departureTime.getUTCMinutes();
  }
  if (startMinutes === undefined) return 0;

  const hours = Number.isFinite(durationHours)
    ? Math.min(24, Math.max(0, durationHours))
    : 0;
  const samples = Math.max(1, Math.min(96, Math.ceil(hours * 4)));
  let sum = 0;
  for (let i = 0; i < samples; i++) {
    sum += circadianPenaltyAtHour(startMinutes / 60 + ((i + 0.5) / samples) * hours);
  }
  return sum / samples;
}

/** `priorMinutes` = minutes already driven before this trip starts. */
function continuousDrivePenalty(priorMinutes: number): number {
  return smoothstep(Math.log1p(Math.max(0, priorMinutes) / 30) / Math.log1p(4));
}

export function computeFatigue(
  features: RouteFeatures,
  ctx: DriverContext
): FatigueResult {
  const durationMinutes = features.durationHours * 60;
  const circadian = circadianPenalty(
    ctx.departureTime,
    ctx.departureLocalMinutes,
    features.durationHours
  );
  const continuous = continuousDrivePenalty(ctx.continuousDriveMinutes);

  // Duration is mostly handled by durationPoints; keep a light log term here.
  const D_fatigue =
    FATIGUE_COEFFICIENTS.a1 * Math.log1p(durationMinutes / 40) +
    FATIGUE_COEFFICIENTS.a2 * circadian +
    FATIGUE_COEFFICIENTS.a3 * continuous;

  const loadFactor = smoothstep((continuous + circadian * 0.7) / 1.6);

  let D_interaction = 0;
  D_interaction += loadFactor * features.monotonyScore * 0.35;
  D_interaction += loadFactor * features.nighttimeShare * 0.35;
  D_interaction +=
    loadFactor * features.mergeBurdenSubscore * features.weaveSectionScore * 0.4;
  D_interaction += loadFactor * features.weatherSeverity * 0.4;
  D_interaction += features.nighttimeShare * features.weatherSeverity * 0.3;
  D_interaction +=
    features.nighttimeShare *
    smoothstep(features.maneuversPer10Mi / 10) *
    0.25;

  return {
    durationMinutes,
    circadianPenalty: circadian,
    continuousPenalty: continuous,
    D_fatigue,
    D_interaction,
  };
}

/**
 * Points (0–10 scale, before clamping and calibration) attributed to each
 * user-facing factor. `explainPrediction` reports these directly, so the
 * stated drivers are the terms that actually produced the score.
 */
export interface RawScoreParts {
  speed: number;
  merges: number;
  turns: number;
  traffic: number;
  length: number;
  fatigue: number;
  weather: number;
  road: number;
  unprotectedLefts: number;
  night: number;
}

export interface RawScoreResult {
  total: number;
  parts: RawScoreParts;
}

const SEGMENT_WEIGHT = 0.42;
const BASE_WEIGHT = 0.28;

/** Delay (minutes) at which a relative slowdown counts in full. */
const FULL_TRAFFIC_DELAY_MINUTES = 6;

export function computeRawScoreParts(
  D_route: number,
  base: BaseScoreComponents,
  fatigue: FatigueResult,
  features: RouteFeatures
): RawScoreResult {
  const parts: RawScoreParts = {
    speed: 0,
    merges: 0,
    turns: 0,
    traffic: 0,
    length: 0,
    fatigue: 0,
    weather: 0,
    road: 0,
    unprotectedLefts: 0,
    night: 0,
  };

  // --- Structure: base components, then the segment aggregate shared among
  // the structural factors in proportion to their base terms. ---
  const structural = {
    speed: BASE_SCORE_WEIGHTS.S * base.S,
    merges: BASE_SCORE_WEIGHTS.M * base.M,
    turns: BASE_SCORE_WEIGHTS.T * base.T,
  };
  const baseTerms = {
    ...structural,
    traffic: BASE_SCORE_WEIGHTS.C * base.C,
    length: BASE_SCORE_WEIGHTS.L * base.L,
  };
  const baseSum = Object.values(baseTerms).reduce((a, b) => a + b, 0);
  // D_base is capped at 1; scale the terms the same way so they sum to it.
  const baseScale = baseSum > 0 ? base.D_base / baseSum : 0;
  parts.speed += baseTerms.speed * baseScale * BASE_WEIGHT * 10;
  parts.merges += baseTerms.merges * baseScale * BASE_WEIGHT * 10;
  parts.turns += baseTerms.turns * baseScale * BASE_WEIGHT * 10;
  parts.traffic += baseTerms.traffic * baseScale * BASE_WEIGHT * 10;
  parts.length += baseTerms.length * baseScale * BASE_WEIGHT * 10;

  const structuralSum = structural.speed + structural.merges + structural.turns;
  const segmentPoints = SEGMENT_WEIGHT * D_route * 10;
  if (structuralSum > 0) {
    parts.speed += (segmentPoints * structural.speed) / structuralSum;
    parts.merges += (segmentPoints * structural.merges) / structuralSum;
    parts.turns += (segmentPoints * structural.turns) / structuralSum;
  } else {
    parts.speed += segmentPoints;
  }

  // --- Timing / load ---
  const fatigueNorm = smoothstep(fatigue.D_fatigue / FATIGUE_NORM_DIVISOR);
  const interactionNorm = smoothstep(fatigue.D_interaction * 2);
  parts.fatigue += (0.08 * fatigueNorm + 0.07 * interactionNorm) * 10;

  // --- Trip length. durationPoints is the single primary duration term. ---
  const sustained = computeSustainedEffortFromHours(features.durationHours).subscore;
  parts.length += 0.08 * sustained * 10;
  parts.length += durationPoints(features.durationHours);
  parts.length +=
    features.monotonyScore *
    smoothstep((features.durationHours - 0.5) / 2.5) *
    0.6;

  // --- Short, simple highway hops are easier than their speed suggests.
  // Each gate is a ramp: the old hard thresholds (65% highway, 45 minutes)
  // moved the score by 0.7 raw points across a one-second difference. ---
  const easyHighwayHop =
    smoothstep((features.highwayShare - 0.45) / 0.3) *
    (1 - smoothstep((D_route - 0.22) / 0.2)) *
    (1 - smoothstep((features.durationHours - 0.5) / 0.5));
  parts.speed -= Math.min(parts.speed, 0.7 * easyHighwayHop);

  // --- Dense local-road navigation, ramped the same way. ---
  const localShare = 1 - smoothstep(features.highwayShare / 0.4);
  parts.turns +=
    localShare * smoothstep((features.maneuversPer10Mi - 2) / 18) * 1.6;
  parts.turns += smoothstep((features.stepsPerMile - 2) / 3) * 0.3;

  // --- Clustering bumps (shared cap of 2 points). ---
  const mergeCluster = Math.max(
    Math.min(1, features.mergeClusterCount / 2),
    Math.min(1, features.weaveCount)
  );
  const mergeBump =
    mergeCluster * (0.05 + features.segmentP90Difficulty * 0.1) +
    features.exponentialSpacing * 0.012 +
    features.laneChangeUrgency * 0.04;
  const turnBump =
    Math.min(1, features.turnClusterCount) *
      (0.05 + features.segmentP90Difficulty * 0.1) +
    Math.min(1, features.closeTurnPairs / 3) *
      (0.03 + smoothstep(features.turnSpacingPressure) * 0.035) +
    smoothstep(features.decisionPointDensity / 5) * 0.05;
  const bump = mergeBump + turnBump;
  const bumpScale = bump > 0.2 ? 0.2 / bump : 1;
  parts.merges += mergeBump * bumpScale * 10;
  parts.turns += turnBump * bumpScale * 10;

  // --- Unprotected lefts. Counted, never as a share: a share term made the
  // score drop when a *protected* left was added to the same route. ---
  parts.unprotectedLefts += smoothstep(features.unprotectedLeftTurns / 4) * 1.3;
  parts.turns += smoothstep(features.leftTurnCount / 12) * 0.1;

  // --- Live weather (not also in D_base). No activation threshold. ---
  const highSpeedExposure =
    features.fractionAbove45Mph * 0.5 + features.fractionAbove60Mph * 0.5;
  parts.weather += Math.min(
    2.6,
    features.weatherSeverity *
      (1.5 + 0.7 * highSpeedExposure + 0.5 * features.nighttimeShare)
  );
  parts.weather += features.icyRisk * 0.5 + features.snowRisk * 0.4;

  // --- Darkness. Previously only reachable through interaction terms, so a
  // fully dark drive scored the same as a daytime one for most routes. ---
  parts.night += features.nighttimeShare * (0.4 + 0.3 * highSpeedExposure);

  // --- Live road context (not also in D_base). ---
  parts.road += features.roadSizeScore * smoothstep(features.urbanShare) * 0.5;
  parts.road += smoothstep(features.unpavedShare / 0.3) * 0.4;
  parts.road += features.constructionSeverity * 0.8;

  // --- Traffic delay. The relative slowdown is damped when the absolute
  // delay is tiny: 40 extra seconds on a two-minute hop is a 33% "delay" but
  // not heavy traffic. ---
  const delayMinutes =
    features.durationHours * 60 * (features.delayRatio / (1 + features.delayRatio));
  const delayWeight =
    0.3 + 0.7 * smoothstep(delayMinutes / FULL_TRAFFIC_DELAY_MINUTES);
  parts.traffic += Math.min(
    2.6,
    smoothstep(features.delayRatio / 0.32) * 2.1 * delayWeight +
      smoothstep(features.trafficVariance) * 0.25
  );

  let total = 0;
  for (const key of Object.keys(parts) as Array<keyof RawScoreParts>) {
    if (!Number.isFinite(parts[key])) parts[key] = 0;
    total += parts[key];
  }
  return { total: Math.min(10, Math.max(0, total)), parts };
}

export function computeRawScore(
  D_route: number,
  base: BaseScoreComponents,
  fatigue: FatigueResult,
  features: RouteFeatures
): number {
  return computeRawScoreParts(D_route, base, fatigue, features).total;
}

export function fatigueSubscore(fatigue: FatigueResult): number {
  return smoothstep(fatigue.D_fatigue / FATIGUE_NORM_DIVISOR);
}
