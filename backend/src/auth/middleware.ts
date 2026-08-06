import type { NextFunction, Request, Response } from "express";
import { createRequestId } from "../errors.js";
import { isDatabaseConfigured } from "../db/pool.js";
import { AuthConfigurationError } from "./errors.js";
import { hasJwtSecret, TokenError, verifyAccessToken } from "./tokens.js";

export interface AuthenticatedUser { id: string; email: string; }

declare module "express-serve-static-core" {
  interface Request { user?: AuthenticatedUser; }
}

function respond(res: Response, status: number, code: "UNAUTHORIZED" | "TOKEN_EXPIRED" | "SERVICE_UNAVAILABLE", error: string): void {
  res.status(status).json({ error, code, requestId: createRequestId() });
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  if (!isDatabaseConfigured() || !hasJwtSecret()) {
    respond(res, 503, "SERVICE_UNAVAILABLE", "Account services are temporarily unavailable. Please try again shortly.");
    return;
  }
  const token = req.header("authorization")?.match(/^Bearer\s+([^\s]+)$/i)?.[1];
  if (!token) {
    respond(res, 401, "UNAUTHORIZED", "Authentication is required.");
    return;
  }
  try {
    req.user = verifyAccessToken(token);
    next();
  } catch (error) {
    if (error instanceof AuthConfigurationError) {
      respond(res, 503, "SERVICE_UNAVAILABLE", "Account services are temporarily unavailable. Please try again shortly.");
    } else if (error instanceof TokenError && error.code === "TOKEN_EXPIRED") {
      respond(res, 401, "TOKEN_EXPIRED", "Access token expired. Refresh your session.");
    } else {
      respond(res, 401, "UNAUTHORIZED", "Authentication token is invalid.");
    }
  }
}
