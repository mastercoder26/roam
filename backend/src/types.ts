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

export interface ScoredRoute {
  score: number;
  uncalibratedScore?: number;
  label: string;
  reasons: string[];
  breakdown: ScoringBreakdown;
  contributions: FactorContribution[];
  uncertainty: ScoreUncertainty;
  hotspots: SegmentHotspot[];
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
  includeAlternates?: boolean;
  continuousDriveMinutes?: number;
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
  continuousDriveMinutes: number;
}

export interface ScoringOptions {
  stepSpeedsMph?: Map<number, number>;
  departureTime?: string;
  continuousDriveMinutes?: number;
  conditions?: RouteConditions;
}

export const MODEL_VERSION = "hybrid-v6";
