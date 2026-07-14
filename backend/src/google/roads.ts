import type { ParsedRoute, SpeedLimitPoint } from "../types.js";
import { samplePolylinePoints } from "../utils/polyline.js";
import { impliedStepSpeedMph, speedLimitToMph } from "../scoring/signals.js";

const SNAP_URL = "https://roads.googleapis.com/v1/snapToRoads";
const SPEED_LIMITS_URL = "https://roads.googleapis.com/v1/speedLimits";

const CHUNK_SIZE = 100;
const CHUNK_OVERLAP = 10;
const TARGET_SAMPLE_COUNT = 80;

interface SnappedPoint {
  placeId: string;
  location: { latitude: number; longitude: number };
  originalIndex?: number;
}

interface SnapResponse {
  snappedPoints?: SnappedPoint[];
  error?: { message?: string; code?: number };
}

interface SpeedLimitEntry {
  placeId: string;
  speedLimit?: number;
  units?: string;
}

interface SpeedLimitsResponse {
  speedLimits?: SpeedLimitEntry[];
  error?: { message?: string; code?: number };
}

function chunkPoints<T>(points: T[], size: number, overlap: number): T[][] {
  if (points.length <= size) return [points];

  const chunks: T[][] = [];
  let start = 0;

  while (start < points.length) {
    const end = Math.min(start + size, points.length);
    chunks.push(points.slice(start, end));
    if (end >= points.length) break;
    start = end - overlap;
  }

  return chunks;
}

async function snapToRoads(
  points: { lat: number; lng: number }[],
  apiKey: string
): Promise<SnappedPoint[]> {
  const path = points.map((p) => `${p.lat},${p.lng}`).join("|");
  const url = `${SNAP_URL}?interpolate=true&path=${encodeURIComponent(path)}&key=${apiKey}`;

  const response = await fetch(url);
  const data = (await response.json()) as SnapResponse;

  if (!response.ok) {
    throw new RoadsAccessError(
      data.error?.message ?? `snapToRoads error: ${response.status}`
    );
  }

  return data.snappedPoints ?? [];
}

async function fetchSpeedLimits(
  placeIds: string[],
  apiKey: string
): Promise<SpeedLimitEntry[]> {
  const results: SpeedLimitEntry[] = [];

  for (let i = 0; i < placeIds.length; i += 100) {
    const batch = placeIds.slice(i, i + 100);
    const params = batch.map((id) => `placeId=${encodeURIComponent(id)}`).join("&");
    const url = `${SPEED_LIMITS_URL}?${params}&key=${apiKey}`;

    const response = await fetch(url);
    const data = (await response.json()) as SpeedLimitsResponse;

    if (!response.ok) {
      throw new RoadsAccessError(
        data.error?.message ?? `speedLimits error: ${response.status}`
      );
    }

    results.push(...(data.speedLimits ?? []));
  }

  return results;
}

export class RoadsAccessError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RoadsAccessError";
  }
}

export async function getSpeedLimitsForRoute(
  route: ParsedRoute,
  apiKey: string
): Promise<SpeedLimitPoint[]> {
  const sampled = samplePolylinePoints(route.polyline, TARGET_SAMPLE_COUNT);
  if (sampled.length === 0) return [];

  const chunks = chunkPoints(sampled, CHUNK_SIZE, CHUNK_OVERLAP);
  const allSnapped: SnappedPoint[] = [];

  for (const chunk of chunks) {
    const snapped = await snapToRoads(chunk, apiKey);
    allSnapped.push(...snapped);
  }

  const uniquePlaceIds = [...new Set(allSnapped.map((p) => p.placeId))];
  if (uniquePlaceIds.length === 0) return [];

  const limits = await fetchSpeedLimits(uniquePlaceIds, apiKey);

  return limits.map((entry) => ({
    placeId: entry.placeId,
    speedLimit: entry.speedLimit,
    speedLimitUnit: entry.units === "KPH" ? "KPH" : "MPH",
  }));
}

/** Map per-step implied or posted speeds in mph for scoring. */
export function buildStepSpeedMap(route: ParsedRoute): Map<number, number> {
  const map = new Map<number, number>();
  route.steps.forEach((step, index) => {
    map.set(index, impliedStepSpeedMph(step));
  });
  return map;
}

/** Merge posted speed limits into step speed map using distance-weighted assignment. */
export function applySpeedLimitsToSteps(
  route: ParsedRoute,
  speedLimits: SpeedLimitPoint[]
): Map<number, number> {
  const stepSpeeds = buildStepSpeedMap(route);

  if (speedLimits.length === 0) return stepSpeeds;

  const limitByPlace = new Map<string, number>();
  for (const limit of speedLimits) {
    if (limit.speedLimit !== undefined) {
      limitByPlace.set(
        limit.placeId,
        speedLimitToMph(limit.speedLimit, limit.speedLimitUnit)
      );
    }
  }

  if (limitByPlace.size === 0) return stepSpeeds;

  const avgLimit =
    [...limitByPlace.values()].reduce((a, b) => a + b, 0) /
    limitByPlace.size;

  route.steps.forEach((step, index) => {
    const implied = impliedStepSpeedMph(step);
    if (avgLimit > 0 && implied > 0) {
      const blend = 0.7 * avgLimit + 0.3 * implied;
      stepSpeeds.set(index, blend);
    } else if (avgLimit > 0) {
      stepSpeeds.set(index, avgLimit);
    }
  });

  return stepSpeeds;
}

export async function enrichRouteWithSpeedLimits(
  route: ParsedRoute,
  apiKey: string
): Promise<Map<number, number>> {
  try {
    const limits = await getSpeedLimitsForRoute(route, apiKey);
    return applySpeedLimitsToSteps(route, limits);
  } catch (error) {
    if (error instanceof RoadsAccessError) {
      return buildStepSpeedMap(route);
    }
    throw error;
  }
}
