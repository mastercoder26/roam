import type { RouteConditions } from "./enrichment/types.js";

export interface LatLng {
  lat: number;
  lng: number;
}

export interface Bounds {
  southwest: LatLng;
  northeast: LatLng;
}

export interface RouteStep {
  distanceMeters: number;
  staticDurationSeconds: number;
  maneuver?: string;
  navigationInstruction?: string;
  polyline?: string;
}

export interface ParsedRoute {
  distanceMeters: number;
  durationSeconds: number;
  staticDurationSeconds: number;
  polyline: string;
  bounds: Bounds;
  steps: RouteStep[];
  routeLabels?: string[];
  /** Advisory warnings from the routing provider (tolls, construction, etc). */
  warnings?: string[];
}

export interface SpeedLimitPoint {
  placeId: string;
  speedLimit?: number;
  speedLimitUnit?: "KPH" | "MPH";
  /** Position in the sampled route polyline, when supplied by Roads API. */
  sampleIndex?: number;
  /** Number of source samples used to query Roads API. */
  sampleCount?: number;
}

export interface ScoringBreakdown {
  speed: number;
  merges: number;
  turns: number;
  traffic: number;
  length: number;
  fatigue: number;
  weather: number;
  road: number;
  /** Legacy aliases for backward compatibility */
  highway: number;
  maneuvers: number;
  navDensity: number;
  effort: number;
}

export interface FactorContribution {
  factor: string;
  label: string;
  value: number;
  weight: number;
  contribution: number;
  share: number;
}

export interface SegmentHotspot {
  segmentIndex: number;
  difficulty: number;
  cumulativeSecondsFromStart: number;
  label?: string;
}

export interface ScoreUncertainty {
  low: number;
  high: number;
  confidence: number;
  spread: number;
}

/** The stable identifiers used by clients to compare route demands with local experience. */
export const ROUTE_DEMAND_IDS = [
  "afterDark",
  "fastRoads",
  "merges",
  "complexIntersections",
  "weatherVisibility",
  "sustainedDrive",
  "traffic",
  "roadConditions",
] as const;

export type RouteDemandId = (typeof ROUTE_DEMAND_IDS)[number];
export type RouteDemandLevel = "low" | "moderate" | "high";

/**
 * A contiguous, ordered portion of the route expressed as a fraction of the
 * validated full-route overview-polyline's geometric length. `startFraction`
 * is inclusive and `endFraction` is exclusive, except that the final range
 * may end at 1. These values intentionally use the same overview geometry
 * that mobile clients decode for local GPS overlap.
 *
 * Ranges are intentionally omitted when the overview geometry or its ordered
 * step mapping cannot be validated. Aggregate enrichment (for example a
 * route-wide weather summary) must not pretend to know the exact section
 * where a condition occurs.
 */
export interface RouteDemandCoverageRange {
  startFraction: number;
  endFraction: number;
}

/**
 * Stable, factual scalar values that give a client enough evidence to compare
 * a planned route with on-device driving history. Keys are demand-specific;
 * values never contain inferred driver behavior.
 */
export type RouteDemandMetrics = Record<string, number>;

/**
 * A factual, normalized description of one thing this route asks of a driver.
 * `available` is false when the route provider could not verify that category.
 */
export interface RouteDemand {
  id: RouteDemandId;
  title: string;
  intensity: number;
  level: RouteDemandLevel;
  evidence: string;
  available: boolean;
  /** Optional factual quantities such as `estimatedMilesAt45`. */
  metrics?: RouteDemandMetrics;
  /**
   * Optional structural coverage on the validated overview polyline. Omitted
   * when geometry cannot be verified or a source only provides an aggregate
   * route-level condition rather than a location.
   */
  coverageRanges?: RouteDemandCoverageRange[];
}

export interface ScoredRoute {
  score: number;
  uncalibratedScore?: number;
  label: string;
  reasons: string[];
  breakdown: ScoringBreakdown;
  contributions: FactorContribution[];
  uncertainty: ScoreUncertainty;
  hotspots: SegmentHotspot[];
  /** Stable, factual route-demand signals for the local readiness assessment. */
  routeDemands: RouteDemand[];
  /** Live conditions (weather, road metadata, construction) used for scoring. */
  conditions?: RouteConditions;
  modelVersion?: string;
  distanceMeters: number;
  durationSeconds: number;
  staticDurationSeconds: number;
  trafficDelaySeconds: number;
  polyline: string;
  bounds: Bounds;
}

export interface AlternateRoute extends ScoredRoute {
  scoreDelta: number;
}

export interface DifficultyResponse {
  primaryRoute: ScoredRoute;
  alternateRoutes: AlternateRoute[];
}

export interface DifficultyRequest {
  origin: string;
  destination: string;
  departureTime?: string;
  /** Local clock minutes at departure (0 = midnight, 1439 = 11:59 PM). */
  departureLocalMinutes?: number;
  includeAlternates?: boolean;
  continuousDriveMinutes?: number;
}

/** One requested departure window for a server-side route comparison. */
export interface DepartureComparisonCandidate {
  /** Stable client-generated identifier, returned unchanged with this result. */
  id: string;
  /** ISO-8601 timestamp representing this candidate departure window. */
  departureTime: string;
  /** Client-local clock minutes for this candidate (0 = midnight). */
  departureLocalMinutes: number;
}

export interface DepartureComparisonRequest {
  origin: string;
  destination: string;
  candidates: DepartureComparisonCandidate[];
}

/**
 * Comparison candidates are deliberately independent. A provider or enrichment
 * failure for one window must not discard useful route data for the others.
 */
export interface DepartureComparisonCandidateResult
  extends DepartureComparisonCandidate {
  route?: ScoredRoute;
  error?: { message: string };
}

export interface DepartureComparisonResponse {
  candidates: DepartureComparisonCandidateResult[];
}

export interface ScoringContext {
  highwayShare: number;
  maneuversPer10Mi: number;
  delayRatio: number;
  stepsPerMile: number;
  durationHours: number;
  breakdown: ScoringBreakdown;
  mergeClusterCount?: number;
  nighttimeShare?: number;
}

export interface DriverContext {
  departureTime?: Date;
  departureLocalMinutes?: number;
  continuousDriveMinutes: number;
}

export interface ScoringOptions {
  stepSpeedsMph?: Map<number, number>;
  departureTime?: string;
  /** Client-local clock minutes, kept separate from the absolute departure timestamp. */
  departureLocalMinutes?: number;
  continuousDriveMinutes?: number;
  conditions?: RouteConditions;
}

export const MODEL_VERSION = "hybrid-v6";
