import type { RouteFeatures } from "./features.js";
import type { ScoreEvidence, ScoreUncertainty } from "../types.js";

/** Hermite smoothstep: x² × (3 - 2x), clamped to [0, 1]. */
export function smoothstep(x: number): number {
  const t = Math.max(0, Math.min(1, x));
  return t * t * (3 - 2 * t);
}

export function scoreToLabel(score: number): string {
  if (score < 2) return "Very Easy";
  if (score < 4) return "Easy";
  if (score < 6) return "Moderate";
  if (score < 8) return "Hard";
  return "Very Hard";
}

const GRACE_HOURS = 0.25;
const MAX_EFFORT_HOURS = 4;

export function computeSustainedEffortFromHours(durationHours: number): {
  durationHours: number;
  subscore: number;
} {
  const effectiveHours = Math.max(0, durationHours - GRACE_HOURS);
  return {
    durationHours,
    subscore: smoothstep(effectiveHours / MAX_EFFORT_HOURS),
  };
}

export function estimateUncertainty(
  features: RouteFeatures,
  evidence: ScoreEvidence,
  residualMagnitude = 0
): ScoreUncertainty {
  let spread = 0.35;
  if (features.mergeClusterCount >= 2) spread += 0.15;
  if (features.durationHours >= 3) spread += 0.1;
  if (features.stepCount < 5) spread += 0.2;
  if (features.exponentialSpacing > 2) spread += 0.1;
  spread += Math.min(0.5, residualMagnitude * 0.2);
  const confidence = Math.max(0.35, Math.min(0.95, 1 - spread / 2));
  return { low: 0, high: 0, confidence, spread, evidence };
}

export function applyUncertaintyBand(
  score: number,
  uncertainty: ScoreUncertainty
): ScoreUncertainty {
  const half = uncertainty.spread / 2;
  return {
    ...uncertainty,
    low: Math.max(0, Math.round((score - half) * 10) / 10),
    high: Math.min(10, Math.round((score + half) * 10) / 10),
  };
}

const CALIBRATION_KNOTS = [
  { x: 0, y: 0 },
  { x: 1.5, y: 1.1 },
  { x: 3, y: 2.5 },
  { x: 4.5, y: 3.8 },
  { x: 6, y: 5.0 },
  { x: 7.5, y: 6.3 },
  { x: 9, y: 7.8 },
  { x: 10, y: 9.0 },
] as const;

/**
 * Maps the heuristic workload to the product's 0–10 difficulty scale.
 *
 * The previous curve treated the upper half of the heuristic score as nearly
 * linear, which made ordinary dense-city trips and traffic delays read as
 * "Very Hard". This conservative curve keeps the ordering intact while
 * reserving 8–10 for routes with several severe, corroborated burdens.
 */
export function calibrateScore(score: number): number {
  const x = Math.max(0, Math.min(10, score));
  const knots = CALIBRATION_KNOTS;
  if (x <= knots[0].x) return knots[0].y;
  if (x >= knots[knots.length - 1].x) return knots[knots.length - 1].y;
  for (let i = 0; i < knots.length - 1; i++) {
    const a = knots[i];
    const b = knots[i + 1];
    if (x >= a.x && x <= b.x) {
      const t = b.x === a.x ? 0 : (x - a.x) / (b.x - a.x);
      return a.y + t * (b.y - a.y);
    }
  }
  return x;
}

export function getCalibrator(): {
  transform: (score: number) => number;
  modelVersion: string;
} {
  return { transform: calibrateScore, modelVersion: "hybrid-v6" };
}
