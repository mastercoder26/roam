import type { ApiFailure, DifficultyResponse } from "./types";
import { departureLocalMinutes, toIsoWithLocalOffset } from "./format";

const API_BASE_URL =
  process.env.NEXT_PUBLIC_ROAM_API_BASE_URL ??
  "https://roam-backend-1059769370189.us-central1.run.app";

export class RoamApiError extends Error {
  code?: string;
  status: number;

  constructor(message: string, status: number, code?: string) {
    super(message);
    this.name = "RoamApiError";
    this.status = status;
    this.code = code;
  }
}

export interface AnalyzeRouteParams {
  origin: string;
  destination: string;
  departureTime: Date;
  includeAlternates?: boolean;
}

/**
 * Calls the same deployed Cloud Run route-analysis backend the iOS app uses
 * (`roam-backend`). It verifies only a Clerk session token
 * (`requireVerifiedIdentity`) and holds no database, so this is the real
 * production scoring pipeline — not a mock.
 */
export async function analyzeRoute(
  params: AnalyzeRouteParams,
  accessToken: string
): Promise<DifficultyResponse> {
  const response = await fetch(`${API_BASE_URL}/api/route/difficulty`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      origin: params.origin.trim(),
      destination: params.destination.trim(),
      departureTime: toIsoWithLocalOffset(params.departureTime),
      departureLocalMinutes: departureLocalMinutes(params.departureTime),
      includeAlternates: params.includeAlternates ?? true,
    }),
  });

  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    // A non-JSON body (e.g. an upstream gateway error page) falls through to
    // the generic message below rather than throwing a parse error.
  }

  if (!response.ok) {
    const failure = (body ?? {}) as Partial<ApiFailure>;
    throw new RoamApiError(
      failure.error ?? `Route analysis failed (HTTP ${response.status}).`,
      response.status,
      failure.code
    );
  }

  return body as DifficultyResponse;
}
