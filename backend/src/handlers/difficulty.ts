import type { Request, Response } from "express";
import { computeRoutes } from "../google/routes.js";
import { enrichRouteWithSpeedLimits } from "../google/roads.js";
import { enrichRoute, neutralConditions } from "../enrichment/index.js";
import { scoreRoutes } from "../scoring/index.js";
import type { DifficultyRequest } from "../types.js";

export function validateDifficultyRequest(body: unknown): DifficultyRequest {
  if (!body || typeof body !== "object") {
    throw new Error("Request body must be a JSON object");
  }

  const {
    origin,
    destination,
    departureTime,
    departureLocalMinutes,
    includeAlternates,
    continuousDriveMinutes,
  } = body as DifficultyRequest;

  if (!origin || typeof origin !== "string") {
    throw new Error("origin is required and must be a string");
  }
  if (!destination || typeof destination !== "string") {
    throw new Error("destination is required and must be a string");
  }
  if (
    departureLocalMinutes !== undefined &&
    (!Number.isInteger(departureLocalMinutes) ||
      departureLocalMinutes < 0 ||
      departureLocalMinutes >= 24 * 60)
  ) {
    throw new Error(
      "departureLocalMinutes must be an integer between 0 and 1439"
    );
  }

  return {
    origin: origin.trim(),
    destination: destination.trim(),
    departureTime:
      typeof departureTime === "string" ? departureTime : undefined,
    departureLocalMinutes:
      typeof departureLocalMinutes === "number"
        ? departureLocalMinutes
        : undefined,
    includeAlternates: includeAlternates ?? false,
    continuousDriveMinutes:
      typeof continuousDriveMinutes === "number"
        ? continuousDriveMinutes
        : undefined,
  };
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
    const routes = await computeRoutes({
      origin: request.origin,
      destination: request.destination,
      departureTime: request.departureTime,
      includeAlternates: request.includeAlternates,
      apiKey,
    });

    const MAX_ENRICHED_ROUTES = 3;

    const [optionsList, conditionsList] = await Promise.all([
      Promise.all(routes.map((route) => enrichRouteWithSpeedLimits(route, apiKey))),
      Promise.all(
        routes.map((route, i) =>
          i < MAX_ENRICHED_ROUTES
            ? enrichRoute(route, { departureTime: request.departureTime })
            : Promise.resolve(neutralConditions())
        )
      ),
    ]);

    const scoreOptions = routes.map((_route, i) => ({
      stepSpeedsMph: optionsList[i],
      departureTime: request.departureTime,
      departureLocalMinutes: request.departureLocalMinutes,
      continuousDriveMinutes: request.continuousDriveMinutes,
      conditions: conditionsList[i],
    }));

    const { primary, alternates } = scoreRoutes(routes, scoreOptions);

    res.status(200).json({
      primaryRoute: primary,
      alternateRoutes: alternates,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "An unexpected error occurred";
    const status =
      message.includes("required") || message.includes("must be") ? 400 : 500;
    res.status(status).json({ error: message });
  }
}
