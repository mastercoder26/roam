import { config } from "dotenv";
import { resolve } from "node:path";
import express from "express";
import type { NextFunction, Request, Response } from "express";
import {
  handleDepartureComparison,
  handleDifficulty,
} from "./src/handlers/difficulty.js";
import { createRequestId, logRateLimited } from "./src/errors.js";
import { createRateLimiter } from "./src/utils/rateLimiter.js";

// `server.ts` lives in `backend/`, alongside the local environment files.
config({ path: resolve(import.meta.dirname, ".env.local") });
config({ path: resolve(import.meta.dirname, ".env") });

// Fail loudly (but not fatally — see the per-request 503 fallback in the
// handlers) so a missing key is obvious at boot instead of on first request.
if (!process.env.GOOGLE_MAPS_API_KEY) {
  console.error(
    "GOOGLE_MAPS_API_KEY is not configured. Route analysis requests will fail until it is set in backend/.env.local."
  );
}

function getAllowedOrigins(): string[] {
  const raw = process.env.ALLOWED_ORIGINS ?? "*";
  if (raw === "*") return ["*"];
  return raw.split(",").map((o) => o.trim()).filter(Boolean);
}

function getRateLimitConfig(): { windowMs: number; maxRequests: number } {
  const windowMs = Number(process.env.RATE_LIMIT_WINDOW_MS ?? 60_000);
  const maxRequests = Number(process.env.RATE_LIMIT_MAX_REQUESTS ?? 30);
  return {
    windowMs: Number.isFinite(windowMs) && windowMs > 0 ? windowMs : 60_000,
    maxRequests: Number.isFinite(maxRequests) && maxRequests > 0 ? maxRequests : 30,
  };
}

const app = express();
const port = Number(process.env.PORT ?? 3000);
const allowedOrigins = getAllowedOrigins();
const rateLimiter = createRateLimiter(getRateLimitConfig());

app.use(express.json());

app.use((req, res, next) => {
  const origin = req.headers.origin ?? "";

  if (allowedOrigins.includes("*")) {
    res.setHeader("Access-Control-Allow-Origin", "*");
  } else if (origin && allowedOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
  }

  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }

  next();
});

/**
 * Both routes below proxy to metered upstream APIs (Google Routes/Roads).
 * Rate limiting is keyed by socket-derived IP, not a client-supplied header,
 * so it cannot be bypassed by spoofing `X-Forwarded-For`.
 */
function rateLimit(endpoint: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const key = req.ip ?? req.socket.remoteAddress ?? "unknown";
    const result = rateLimiter.check(key);

    if (!result.allowed) {
      const requestId = createRequestId();
      logRateLimited(requestId, { endpoint });
      res.setHeader("Retry-After", String(result.retryAfterSeconds));
      res.status(429).json({
        error: "Too many requests. Please slow down and try again shortly.",
        code: "RATE_LIMITED",
        requestId,
      });
      return;
    }

    next();
  };
}

app.post("/api/route/difficulty", rateLimit("difficulty"), (req, res) => {
  void handleDifficulty(req, res);
});

app.post("/api/route/departure-comparison", rateLimit("departure-comparison"), (req, res) => {
  void handleDepartureComparison(req, res);
});

const server = app.listen(port, () => {
  console.log(`Roam API listening on http://localhost:${port}`);
});

server.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EADDRINUSE") {
    console.error(
      `Port ${port} is already in use. Stop the existing Roam API, or start this one with PORT=3001 npm run dev.`,
    );
  } else {
    console.error("Roam API failed to start:", error);
  }

  process.exitCode = 1;
});
