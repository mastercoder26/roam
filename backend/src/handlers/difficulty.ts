import type { Request, Response } from "express";
import { computeRoutes } from "../google/routes.js";
import { enrichRouteWithSpeedLimits } from "../google/roads.js";
import { enrichRoute, neutralConditions } from "../enrichment/index.js";
import { scoreRoutes } from "../scoring/index.js";
import type {
  DepartureComparisonCandidate,
  DepartureComparisonRequest,
  DepartureComparisonResponse,
  DifficultyRequest,
  DifficultyResponse,
} from "../types.js";

const MAX_ENRICHED_ROUTES = 3;

/** Distinguishes malformed client input from provider and internal failures. */
class RequestValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RequestValidationError";
  }
}

const routeAnalysisDependencies = {
  computeRoutes,
  enrichRouteWithSpeedLimits,
  enrichRoute,
  neutralConditions,
  scoreRoutes,
};

/** Injectable only so the route pipeline can be verified without network calls. */
export type RouteAnalysisDependencies = typeof routeAnalysisDependencies;

function validateAddress(value: unknown, field: "origin" | "destination"): string {
  if (!value || typeof value !== "string" || !value.trim()) {
    throw new RequestValidationError(`${field} is required and must be a string`);
  }
  return value.trim();
}

function validateDepartureLocalMinutes(value: unknown): number | undefined {
  if (value === undefined) return undefined;
  if (
    !Number.isInteger(value) ||
    typeof value !== "number" ||
    value < 0 ||
    value >= 24 * 60
  ) {
    throw new RequestValidationError(
      "departureLocalMinutes must be an integer between 0 and 1439"
    );
  }
  return value;
}

const ISO_TIMESTAMP = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

function isValidIsoTimestamp(value: string): boolean {
  const match = value.match(ISO_TIMESTAMP);
  if (!match || Number.isNaN(Date.parse(value))) return false;

  const [, yearText, monthText, dayText, hourText, minuteText, secondText, zone] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = secondText === undefined ? 0 : Number(secondText);

  if (
    month < 1 || month > 12 ||
    day < 1 || day > new Date(Date.UTC(year, month, 0)).getUTCDate() ||
    hour > 23 || minute > 59 || second > 59
  ) {
    return false;
  }

  if (zone !== "Z") {
    const [offsetHours, offsetMinutes] = zone.slice(1).split(":").map(Number);
    if (offsetHours > 23 || offsetMinutes > 59) return false;
  }

  return true;
}

function validateDepartureTime(value: unknown): string {
  if (typeof value !== "string" || !isValidIsoTimestamp(value)) {
    throw new RequestValidationError("departureTime must be a valid ISO-8601 timestamp");
  }
  return value;
}

export function validateDifficultyRequest(body: unknown): DifficultyRequest {
  if (!body || typeof body !== "object") {
    throw new RequestValidationError("Request body must be a JSON object");
  }

  const {
    origin,
    destination,
    departureTime,
    departureLocalMinutes,
    includeAlternates,
    continuousDriveMinutes,
  } = body as DifficultyRequest;

  return {
    origin: validateAddress(origin, "origin"),
    destination: validateAddress(destination, "destination"),
    departureTime:
      typeof departureTime === "string" ? departureTime : undefined,
    departureLocalMinutes: validateDepartureLocalMinutes(departureLocalMinutes),
    includeAlternates: includeAlternates ?? false,
    continuousDriveMinutes:
      typeof continuousDriveMinutes === "number"
        ? continuousDriveMinutes
        : undefined,
  };
}

export function validateDepartureComparisonRequest(
  body: unknown
): DepartureComparisonRequest {
  if (!body || typeof body !== "object") {
    throw new RequestValidationError("Request body must be a JSON object");
  }

  const { origin, destination, candidates } = body as Partial<DepartureComparisonRequest>;
  if (!Array.isArray(candidates) || candidates.length < 1 || candidates.length > 3) {
    throw new RequestValidationError("candidates must contain between 1 and 3 items");
  }

  const seenIds = new Set<string>();
  const parsedCandidates = candidates.map((candidate, index): DepartureComparisonCandidate => {
    if (!candidate || typeof candidate !== "object") {
      throw new RequestValidationError(`candidates[${index}] must be an object`);
    }

    const { id, departureTime, departureLocalMinutes } = candidate;
    if (typeof id !== "string" || !id.trim()) {
      throw new RequestValidationError(`candidates[${index}].id is required and must be a string`);
    }

    const normalizedId = id.trim();
    if (seenIds.has(normalizedId)) {
      throw new RequestValidationError("candidate ids must be unique");
    }
    seenIds.add(normalizedId);

    const localMinutes = validateDepartureLocalMinutes(departureLocalMinutes);
    if (localMinutes === undefined) {
      throw new RequestValidationError(
        `candidates[${index}].departureLocalMinutes is required and must be an integer between 0 and 1439`
      );
    }

    return {
      id: normalizedId,
      departureTime: validateDepartureTime(departureTime),
      departureLocalMinutes: localMinutes,
    };
  });

  return {
    origin: validateAddress(origin, "origin"),
    destination: validateAddress(destination, "destination"),
    candidates: parsedCandidates,
  };
}

/**
 * The common routing, enrichment, and scoring pipeline. It intentionally
 * remains the only place that combines provider data into a scored route.
 */
export async function analyzeDifficultyRequest(
  request: DifficultyRequest,
  apiKey: string,
  dependencies: RouteAnalysisDependencies = routeAnalysisDependencies
): Promise<DifficultyResponse> {
  const routes = await dependencies.computeRoutes({
    origin: request.origin,
    destination: request.destination,
    departureTime: request.departureTime,
    includeAlternates: request.includeAlternates,
    apiKey,
  });

  const [optionsList, conditionsList] = await Promise.all([
    Promise.all(routes.map((route) => dependencies.enrichRouteWithSpeedLimits(route, apiKey))),
    Promise.all(
      routes.map((route, index) =>
        index < MAX_ENRICHED_ROUTES
          ? dependencies.enrichRoute(route, { departureTime: request.departureTime })
          : Promise.resolve(dependencies.neutralConditions())
      )
    ),
  ]);

  const scoreOptions = routes.map((_route, index) => ({
    stepSpeedsMph: optionsList[index],
    departureTime: request.departureTime,
    departureLocalMinutes: request.departureLocalMinutes,
    continuousDriveMinutes: request.continuousDriveMinutes,
    conditions: conditionsList[index],
  }));

  const { primary, alternates } = dependencies.scoreRoutes(routes, scoreOptions);
  return { primaryRoute: primary, alternateRoutes: alternates };
}

/**
 * Scores each requested time independently. A route provider failure is a
 * useful unavailable result for that one time, not a failure of the request.
 */
export async function analyzeDepartureComparisonRequest(
  request: DepartureComparisonRequest,
  apiKey: string,
  dependencies: RouteAnalysisDependencies = routeAnalysisDependencies
): Promise<DepartureComparisonResponse> {
  const candidates = await Promise.all(
    request.candidates.map(async (candidate) => {
      try {
        const response = await analyzeDifficultyRequest(
          {
            origin: request.origin,
            destination: request.destination,
            departureTime: candidate.departureTime,
            departureLocalMinutes: candidate.departureLocalMinutes,
            includeAlternates: false,
          },
          apiKey,
          dependencies
        );

        return { ...candidate, route: response.primaryRoute };
      } catch (error) {
        return {
          ...candidate,
          error: {
            message:
              error instanceof Error ? error.message : "Route analysis is unavailable",
          },
        };
      }
    })
  );

  return { candidates };
}

export async function handleDifficulty(
  req: Request,
  res: Response
): Promise<void> {
  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: "GOOGLE_MAPS_API_KEY is not configured" });
    return;
  }

  try {
    const request = validateDifficultyRequest(req.body);
    const { primaryRoute: primary, alternateRoutes: alternates } =
      await analyzeDifficultyRequest(request, apiKey);

    res.status(200).json({
      primaryRoute: primary,
      alternateRoutes: alternates,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "An unexpected error occurred";
    const status = error instanceof RequestValidationError ? 400 : 500;
    res.status(status).json({ error: message });
  }
}

export async function handleDepartureComparison(
  req: Request,
  res: Response
): Promise<void> {
  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: "GOOGLE_MAPS_API_KEY is not configured" });
    return;
  }

  try {
    const request = validateDepartureComparisonRequest(req.body);
    const response = await analyzeDepartureComparisonRequest(request, apiKey);
    res.status(200).json(response);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "An unexpected error occurred";
    const status = error instanceof RequestValidationError ? 400 : 500;
    res.status(status).json({ error: message });
  }
}
