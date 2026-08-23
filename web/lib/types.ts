// Ported from backend/src/types.ts and ios/Roam/Models/RouteDifficultyModels.swift.
// This is the exact wire contract the deployed Cloud Run backend returns from
// POST /api/route/difficulty, so the web demo can render the real response
// with no reinterpretation.

export interface LatLng {
  lat: number;
  lng: number;
}

export interface Bounds {
  southwest: LatLng;
  northeast: LatLng;
}

export type RouteDemandLevel = "low" | "moderate" | "high";

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

export interface RouteDemandCoverageRange {
  startFraction: number;
  endFraction: number;
}

export interface RouteDemand {
  id: RouteDemandId | string;
  title: string;
  intensity: number;
  level: RouteDemandLevel;
  evidence: string;
  available: boolean;
  metrics?: Record<string, number>;
  coverageRanges?: RouteDemandCoverageRange[];
}

export type ScoreEvidenceSignal =
  | "routeGeometry"
  | "trafficTiming"
  | "speedLimits"
  | "weather"
  | "roadMetadata"
  | "turnControls";

export type ScoreEvidenceLevel = "limited" | "partial" | "wellSupported";

export interface ScoreEvidence {
  schemaVersion: string;
  inputCoverage: number;
  level: ScoreEvidenceLevel;
  predictiveValidation: "notValidated";
  signalCoverage: Record<ScoreEvidenceSignal, number>;
  verifiedSignals: ScoreEvidenceSignal[];
  missingSignals: ScoreEvidenceSignal[];
}

export interface ScoreUncertainty {
  low: number;
  high: number;
  confidence: number;
  spread: number;
  evidence: ScoreEvidence;
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

export interface WeatherConditions {
  available: boolean;
  condition: string;
  severity: number;
  precipIntensity: number;
  snowRisk: number;
  windSeverity: number;
  lowVisibilityRisk: number;
  icyRisk: number;
  temperatureF: number;
  windGustMph: number;
  visibilityMiles: number;
}

export interface RoadConditions {
  available: boolean;
  avgLanes: number;
  narrowRoadShare: number;
  majorRoadShare: number;
  unpavedShare: number;
  roadSizeScore: number;
  constructionZones: number;
  dominantRoadClass: string;
  classCounts: Record<string, number>;
}

export interface TurnExposure {
  available: boolean;
  unprotectedLeftTurns: number;
  protectedLeftTurns: number;
  unprotectedTurnShare: number;
}

export interface RouteConditions {
  weather: WeatherConditions;
  road: RoadConditions;
  turns: TurnExposure;
  sources: string[];
}

export type DifficultyLabel =
  | "Very Easy"
  | "Easy"
  | "Moderate"
  | "Hard"
  | "Very Hard";

export interface ScoredRoute {
  score: number;
  uncalibratedScore?: number;
  label: DifficultyLabel;
  reasons: string[];
  breakdown: ScoringBreakdown;
  contributions: FactorContribution[];
  uncertainty: ScoreUncertainty;
  hotspots: SegmentHotspot[];
  routeDemands: RouteDemand[];
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

export interface ApiFailure {
  error: string;
  code?: string;
  requestId?: string;
}
