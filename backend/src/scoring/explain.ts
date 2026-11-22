import type { FactorContribution, ScoringBreakdown, ScoringContext, SegmentHotspot } from "../types.js";
import { BASE_SCORE_WEIGHTS, type BaseScoreComponents } from "./baseScore.js";
import type { FatigueResult } from "./fatigue.js";
import { durationBurden, fatigueSubscore, type RawScoreParts } from "./fatigue.js";
import type { RouteFeatures } from "./features.js";
import {
  METERS_PER_MILE,
  computeSustainedEffortFromHours,
  finiteOr,
  smoothstep,
} from "./helpers.js";
import type { RouteSegment } from "./segments.js";

const FACTOR_LABELS: Record<string, string> = {
  speed: "High-speed road burden",
  merges: "Merge/interchange burden",
  turns: "Maneuver burden",
  traffic: "Traffic burden",
  length: "Length/monotony burden",
  fatigue: "Drive timing / load",
  weather: "Weather conditions",
  road: "Road size/conditions",
  turnCluster: "Turn clustering pressure",
  decisionDensity: "Dense decision windows",
  sustained: "Sustained attention",
  laneChange: "Lane change urgency",
  unprotectedLefts: "Unprotected left turns",
  night: "Driving after dark",
};

/**
 * Interpretive weights: the five structural factors are derived from
 * BASE_SCORE_WEIGHTS rather than restated, because these weights rank the
 * factors shown to the user and a copy drifts. `traffic` had drifted to 0.20
 * against a real weight of 0.14, over-ranking it by ~43% and letting the
 * stated top reason disagree with what actually drove the score.
 *
 * The remaining three have no base counterpart — they are live overlays
 * applied as additive points in computeRawScore, so their interpretive
 * weight is a presentation choice, not a mirror of a scoring constant.
 */
export const FACTOR_WEIGHTS: Record<
  keyof Pick<
    ScoringBreakdown,
    | "speed"
    | "merges"
    | "turns"
    | "traffic"
    | "length"
    | "fatigue"
    | "weather"
    | "road"
  >,
  number
> = {
  speed: BASE_SCORE_WEIGHTS.S,
  merges: BASE_SCORE_WEIGHTS.M,
  turns: BASE_SCORE_WEIGHTS.T,
  traffic: BASE_SCORE_WEIGHTS.C,
  length: BASE_SCORE_WEIGHTS.L,
  fatigue: 0.1,
  weather: 0.18,
  road: 0.1,
};

export function buildBreakdown(
  base: BaseScoreComponents,
  fatigue: FatigueResult,
  durationHours: number
): ScoringBreakdown {
  const fatigueScore = fatigueSubscore(fatigue);
  const sustained = computeSustainedEffortFromHours(durationHours).subscore;
  const durationScore = durationBurden(durationHours);
  return {
    speed: base.S,
    merges: base.M,
    turns: base.T,
    traffic: base.C,
    length: Math.max(base.L, durationScore),
    fatigue: fatigueScore,
    weather: base.W,
    road: base.R,
    highway: base.S,
    maneuvers: base.T,
    navDensity: base.T,
    effort: Math.max(sustained, base.L, fatigueScore, durationScore),
  };
}

/**
 * Factor contributions are the points each factor actually added in
 * `computeRawScoreParts` (expressed as a 0–1 fraction of the 10-point scale),
 * not a second, presentation-only weighting. The top contribution is therefore
 * always the term that moved the score most.
 */
export function explainPrediction(
  breakdown: ScoringBreakdown,
  features: RouteFeatures,
  parts: RawScoreParts
): FactorContribution[] {
  const values: Record<keyof RawScoreParts, number> = {
    speed: breakdown.speed,
    merges: breakdown.merges,
    turns: breakdown.turns,
    traffic: breakdown.traffic,
    length: breakdown.length,
    fatigue: breakdown.fatigue,
    weather: breakdown.weather ?? 0,
    road: breakdown.road ?? 0,
    unprotectedLefts: smoothstep(features.unprotectedLeftTurns / 4),
    night: features.nighttimeShare,
  };
  const optional = new Set<keyof RawScoreParts>([
    "weather",
    "road",
    "unprotectedLefts",
    "night",
  ]);

  const entries: FactorContribution[] = (
    Object.keys(parts) as Array<keyof RawScoreParts>
  )
    // Hide overlay factors entirely when they added nothing.
    .filter((key) => !optional.has(key) || parts[key] > 0.02)
    .map((key) => {
      const value = finiteOr(values[key]);
      const contribution = Math.max(0, finiteOr(parts[key])) / 10;
      return {
        factor: key,
        label: FACTOR_LABELS[key] ?? key,
        value,
        weight: value > 0 ? contribution / value : 0,
        contribution,
        share: 0,
      };
    });

  const total = entries.reduce((sum, e) => sum + e.contribution, 0) || 1;
  for (const entry of entries) {
    entry.share = Math.round((entry.contribution / total) * 1000) / 1000;
  }

  entries.sort((a, b) => b.contribution - a.contribution);
  return entries;
}

export function buildHotspots(
  segments: RouteSegment[],
  segmentScores: number[],
  limit = 5
): SegmentHotspot[] {
  const indexed = segmentScores.map((score, i) => ({
    segment: segments[i],
    score,
  }));

  indexed.sort((a, b) => b.score - a.score);

  return indexed.slice(0, limit).map(({ segment, score }) => ({
    segmentIndex: segment.index,
    difficulty: Math.round(score * 1000) / 1000,
    cumulativeSecondsFromStart: segment.cumulativeSecondsFromStart,
    label: summarizeSegment(segment),
  }));
}

function summarizeSegment(segment: RouteSegment): string {
  const miles = (segment.distanceMeters / METERS_PER_MILE).toFixed(1);
  const mergeLike = segment.maneuvers.filter(
    (m) => m === "MERGE" || m.startsWith("RAMP_")
  ).length;

  const turnManeuvers = segment.maneuvers.filter(
    (m) =>
      m.startsWith("TURN_") ||
      m.startsWith("FORK_") ||
      m.startsWith("ROUNDABOUT_") ||
      m.startsWith("UTURN_")
  );
  const sharpTurns = turnManeuvers.filter(
    (m) => m.includes("SHARP") || m.startsWith("UTURN_") || m.startsWith("ROUNDABOUT_")
  ).length;

  if (mergeLike >= 2) return `Dense merge cluster (~${miles} mi)`;
  if (mergeLike === 1 && segment.impliedSpeedMph >= 55) {
    return `Lane-change section (~${miles} mi)`;
  }
  if (sharpTurns >= 2) return `Sharp turn cluster (~${miles} mi)`;
  if (turnManeuvers.length >= 2 && segment.distanceMeters / METERS_PER_MILE < 0.3) {
    return `Back-to-back turns (~${miles} mi)`;
  }
  if (segment.maneuvers.length >= 3) return `Multiple turns (~${miles} mi)`;
  if (segment.isHighway && segment.impliedSpeedMph >= 60) {
    return `High-speed segment (~${miles} mi)`;
  }
  return `Local segment (~${miles} mi)`;
}

// --- Human-readable reasons ---

const FACTOR_REASONS: Array<{
  key: keyof ScoringBreakdown;
  threshold: number;
  message: string;
}> = [
  { key: "speed", threshold: 0.55, message: "High-speed environment" },
  { key: "merges", threshold: 0.5, message: "Complex merges/exchanges" },
  { key: "turns", threshold: 0.55, message: "Many turns" },
  { key: "traffic", threshold: 0.5, message: "Heavy traffic" },
  { key: "length", threshold: 0.55, message: "Long drive" },
  { key: "fatigue", threshold: 0.45, message: "Demanding drive timing" },
];

const REASON_WEIGHTS: Record<string, number> = {
  speed: 0.24,
  merges: 0.26,
  turns: 0.22,
  traffic: BASE_SCORE_WEIGHTS.C,
  length: 0.14,
  fatigue: 0.1,
};

export function generateReasons(
  ctx: ScoringContext,
  features?: RouteFeatures,
  _base?: BaseScoreComponents,
  fatigue?: FatigueResult
): string[] {
  const reasons: Array<{ text: string; weight: number }> = [];

  for (const rule of FACTOR_REASONS) {
    const value = ctx.breakdown[rule.key] ?? 0;
    // The speed component also carries local-road burden, so it can be high
    // on a route with no fast roads at all. Only call it high-speed when the
    // route really is.
    if (rule.key === "speed" && features && features.fractionAbove45Mph < 0.5) {
      continue;
    }
    if (value >= rule.threshold) {
      reasons.push({ text: rule.message, weight: (REASON_WEIGHTS[rule.key] ?? 0.1) * value });
    }
  }

  if (!features) {
    return dedupeAndLimit(reasons);
  }

  if (features.weaveCount >= 2) {
    reasons.push({ text: "Weaving between exits", weight: 0.24 });
  }

  if (features.mergeClusterCount >= 2) {
    reasons.push({ text: "Clustered interchanges", weight: 0.22 });
  } else if (features.exponentialSpacing > 2.5 && features.mergeCount >= 2) {
    reasons.push({ text: "Merges close together", weight: 0.2 });
  }

  if (features.turnClusterCount >= 1) {
    reasons.push({ text: "Turns close together", weight: 0.21 });
  }

  if (features.closeTurnPairs >= 2) {
    reasons.push({ text: "Back-to-back turns", weight: 0.23 });
  }

  if (features.decisionPointDensity >= 3) {
    reasons.push({ text: "Dense decision windows", weight: 0.19 });
  }

  if (features.laneChangeUrgency >= 0.4) {
    reasons.push({ text: "Frequent lane changes", weight: 0.18 });
  }

  if (features.unprotectedLeftTurns >= 2) {
    reasons.push({
      text: "Unprotected left turns",
      weight: 0.26 + features.unprotectedTurnShare * 0.1,
    });
  } else if (features.leftTurnCount >= 4) {
    reasons.push({ text: "Multiple left turns", weight: 0.17 });
  }

  if (features.sharpTurnCount >= 2) {
    reasons.push({ text: "Sharp turns or U-turns", weight: 0.2 });
  }

  if (features.snowRisk >= 0.25 || features.icyRisk >= 0.5) {
    reasons.push({ text: "Snow or ice expected", weight: 0.3 });
  } else if (features.precipIntensity >= 0.25) {
    reasons.push({ text: "Rain at drive time", weight: 0.24 });
  }

  if (features.windSeverity >= 0.4) {
    reasons.push({ text: "Strong wind gusts", weight: 0.2 });
  }

  if (features.lowVisibilityRisk >= 0.4) {
    reasons.push({ text: "Low visibility expected", weight: 0.22 });
  }

  if (features.constructionZones >= 1) {
    reasons.push({
      text:
        features.constructionZones >= 3
          ? "Multiple construction zones"
          : "Construction along the route",
      weight: 0.21,
    });
  }

  if (features.unpavedShare >= 0.1) {
    reasons.push({ text: "Unpaved road sections", weight: 0.2 });
  }

  if (features.roadSizeScore >= 0.55 && features.narrowRoadShare >= 0.3) {
    reasons.push({ text: "Narrow local roads", weight: 0.18 });
  }

  const sustained = computeSustainedEffortFromHours(features.durationHours).subscore;
  if (sustained >= 0.5 && features.durationHours >= 2) {
    reasons.push({ text: "Sustained attention required", weight: 0.16 });
  }

  if (features.monotonyScore >= 0.4 && features.durationHours >= 1.5) {
    reasons.push({ text: "Long monotonous stretch", weight: 0.15 });
  }

  if (ctx.highwayShare >= 0.65) {
    reasons.push({ text: "Mostly highway", weight: 0.12 });
  } else if (ctx.highwayShare <= 0.2) {
    reasons.push({ text: "Mostly local roads", weight: 0.18 });
  }

  if (
    ctx.highwayShare < 0.25 &&
    ctx.maneuversPer10Mi >= 8 &&
    !reasons.some((r) => r.text === "Many turns")
  ) {
    reasons.push({ text: "Urban grid navigation", weight: 0.2 });
  }

  if (ctx.delayRatio >= 0.2) {
    reasons.push({
      text: ctx.delayRatio >= 0.35 ? "Heavy traffic" : "Moderate traffic",
      weight: 0.15 + ctx.delayRatio,
    });
  }

  if (ctx.durationHours >= 2.5) {
    reasons.push({ text: "Long sustained drive", weight: 0.14 });
  }

  if (fatigue && fatigue.circadianPenalty > 0.5) {
    reasons.push({ text: "Late-night driving window", weight: 0.16 });
  }

  if (fatigue && fatigue.continuousPenalty > 0.4) {
    reasons.push({ text: "Already been driving a while", weight: 0.15 });
  }

  if (features.segmentMaxDifficulty >= 0.6) {
    reasons.push({ text: "Demanding segment hotspot", weight: 0.19 });
  }

  return dedupeAndLimit(reasons);
}

function dedupeAndLimit(reasons: Array<{ text: string; weight: number }>): string[] {
  reasons.sort((a, b) => b.weight - a.weight);
  const unique: string[] = [];
  for (const r of reasons) {
    if (!unique.includes(r.text)) unique.push(r.text);
    if (unique.length >= 6) break;
  }
  return unique;
}
