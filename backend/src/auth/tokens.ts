import { createHmac, timingSafeEqual } from "node:crypto";
import { AuthConfigurationError } from "./errors.js";
import type { AuthenticatedUser } from "./types.js";

export type AuthTokenUser = AuthenticatedUser;
export type AccessTokenUser = AuthTokenUser;
export interface AccessTokenPayload extends AuthTokenUser {
  sub: string;
  iat: number;
  exp: number;
}

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const ACCESS_TOKEN_SECONDS = ACCESS_TOKEN_TTL_SECONDS;

export class TokenError extends Error {
  constructor(readonly code: "UNAUTHORIZED" | "TOKEN_EXPIRED", message: string) {
    super(message);
    this.name = "TokenError";
  }
}

export function hasJwtSecret(): boolean {
  return Boolean(process.env.JWT_SECRET?.trim());
}

function getSecret(secret?: string): string {
  const resolved = secret ?? process.env.JWT_SECRET?.trim();
  if (!resolved) throw new AuthConfigurationError("JWT_SECRET is not configured.");
  return resolved;
}

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function signature(input: string, secret: string): string {
  return createHmac("sha256", secret).update(input).digest("base64url");
}

export function issueAccessToken(
  user: AuthTokenUser,
  secret?: string,
  nowMs = Date.now(),
  ttlSeconds = ACCESS_TOKEN_TTL_SECONDS
): string {
  const issuedAt = Math.floor(nowMs / 1_000);
  const header = encode({ alg: "HS256", typ: "JWT" });
  const payload = encode({ sub: user.id, email: user.email, iat: issuedAt, exp: issuedAt + ttlSeconds });
  const signingInput = `${header}.${payload}`;
  return `${signingInput}.${signature(signingInput, getSecret(secret))}`;
}

export function verifyAccessToken(token: string, secret?: string, nowMs = Date.now()): AuthTokenUser {
  const parts = token.split(".");
  if (parts.length !== 3) throw new TokenError("UNAUTHORIZED", "Invalid access token");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const expected = Buffer.from(signature(`${encodedHeader}.${encodedPayload}`, getSecret(secret)), "base64url");
  const received = Buffer.from(encodedSignature, "base64url");
  if (expected.length !== received.length || !timingSafeEqual(expected, received)) {
    throw new TokenError("UNAUTHORIZED", "Invalid access token");
  }

  try {
    const header = JSON.parse(Buffer.from(encodedHeader, "base64url").toString("utf8")) as { alg?: string; typ?: string };
    const payload = JSON.parse(Buffer.from(encodedPayload, "base64url").toString("utf8")) as Partial<AccessTokenPayload>;
    if (header.alg !== "HS256" || header.typ !== "JWT" || typeof payload.sub !== "string" || typeof payload.email !== "string" || typeof payload.exp !== "number") {
      throw new TokenError("UNAUTHORIZED", "Invalid access token");
    }
    if (payload.exp <= Math.floor(nowMs / 1_000)) {
      throw new TokenError("TOKEN_EXPIRED", "Access token has expired");
    }
    return { id: payload.sub, email: payload.email };
  } catch (error) {
    if (error instanceof TokenError) throw error;
    throw new TokenError("UNAUTHORIZED", "Invalid access token");
  }
}
