import type { Bounds, LatLng, ParsedRoute, RouteStep } from "../types.js";
import { parseDurationSeconds } from "../utils/polyline.js";

const ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";

const FIELD_MASK = [
  "routes.duration",
  "routes.staticDuration",
  "routes.distanceMeters",
  "routes.polyline.encodedPolyline",
  "routes.routeLabels",
  "routes.warnings",
  "routes.legs.steps.distanceMeters",
  "routes.legs.steps.staticDuration",
  "routes.legs.steps.navigationInstruction",
  "routes.legs.steps.polyline.encodedPolyline",
  "routes.viewport",
].join(",");

interface ComputeRoutesParams {
  origin: string;
  destination: string;
  departureTime?: string;
  includeAlternates?: boolean;
  apiKey: string;
}

interface GoogleLatLng {
  latitude: number;
  longitude: number;
}

interface GoogleViewport {
  low: GoogleLatLng;
  high: GoogleLatLng;
}

interface GoogleNavigationInstruction {
  maneuver?: string;
  instructions?: string;
}

interface GoogleStep {
  distanceMeters?: number;
  staticDuration?: string;
  navigationInstruction?: GoogleNavigationInstruction;
  polyline?: { encodedPolyline?: string };
}

interface GoogleLeg {
  steps?: GoogleStep[];
}

interface GoogleRoute {
  duration?: string;
  staticDuration?: string;
  distanceMeters?: number;
  polyline?: { encodedPolyline?: string };
  routeLabels?: string[];
  warnings?: string[];
  legs?: GoogleLeg[];
  viewport?: GoogleViewport;
}

interface ComputeRoutesResponse {
  routes?: GoogleRoute[];
  error?: { message?: string; code?: number };
}

function toLatLng(point: GoogleLatLng): LatLng {
  return { lat: point.latitude, lng: point.longitude };
}

function parseBounds(viewport?: GoogleViewport): Bounds {
  if (!viewport?.low || !viewport?.high) {
    return {
      southwest: { lat: 0, lng: 0 },
      northeast: { lat: 0, lng: 0 },
    };
  }
  return {
    southwest: toLatLng(viewport.low),
    northeast: toLatLng(viewport.high),
  };
}

function parseSteps(legs?: GoogleLeg[]): RouteStep[] {
  if (!legs) return [];

  const steps: RouteStep[] = [];
  for (const leg of legs) {
    for (const step of leg.steps ?? []) {
      steps.push({
        distanceMeters: step.distanceMeters ?? 0,
        staticDurationSeconds: parseDurationSeconds(step.staticDuration),
        maneuver: step.navigationInstruction?.maneuver,
        navigationInstruction: step.navigationInstruction?.instructions,
        polyline: step.polyline?.encodedPolyline,
      });
    }
  }
  return steps;
}

function parseRoute(route: GoogleRoute): ParsedRoute {
  return {
    distanceMeters: route.distanceMeters ?? 0,
    durationSeconds: parseDurationSeconds(route.duration),
    staticDurationSeconds: parseDurationSeconds(route.staticDuration),
    polyline: route.polyline?.encodedPolyline ?? "",
    bounds: parseBounds(route.viewport),
    steps: parseSteps(route.legs),
    routeLabels: route.routeLabels,
    warnings: route.warnings,
  };
}

export async function computeRoutes(
  params: ComputeRoutesParams
): Promise<ParsedRoute[]> {
  const body: Record<string, unknown> = {
    origin: { address: params.origin },
    destination: { address: params.destination },
    travelMode: "DRIVE",
    routingPreference: "TRAFFIC_AWARE_OPTIMAL",
    computeAlternativeRoutes: params.includeAlternates ?? false,
    units: "IMPERIAL",
  };

  if (params.departureTime) {
    body.departureTime = params.departureTime;
  }

  const response = await fetch(ROUTES_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": params.apiKey,
      "X-Goog-FieldMask": FIELD_MASK,
    },
    body: JSON.stringify(body),
  });

  const data = (await response.json()) as ComputeRoutesResponse;

  if (!response.ok) {
    const message =
      data.error?.message ?? `Routes API error: ${response.status}`;
    throw new Error(message);
  }

  const routes = data.routes ?? [];
  if (routes.length === 0) {
    throw new Error("No routes found between origin and destination");
  }

  return routes.map(parseRoute);
}
