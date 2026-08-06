import { createHash, randomBytes } from "node:crypto";
import {
  createRefreshToken,
  findRefreshTokenByHash,
  revokeAllRefreshTokens,
  revokeRefreshToken,
  type RefreshTokenRecord,
} from "../db/repositories/refreshTokens.js";
import { InvalidRefreshTokenError, RefreshTokenReuseError } from "./errors.js";

export { RefreshTokenReuseError } from "./errors.js";

export interface RefreshTokenRepository {
  findByHash(hash: string): Promise<RefreshTokenRecord | null>;
  revoke(id: string): Promise<void>;
  revokeAllForUser(userId: string): Promise<void>;
  create(input: { userId: string; tokenHash: string; expiresAt: Date; userAgent: string | null }): Promise<RefreshTokenRecord>;
}

const databaseRepository: RefreshTokenRepository = {
  findByHash: findRefreshTokenByHash,
  revoke: revokeRefreshToken,
  revokeAllForUser: revokeAllRefreshTokens,
  create: createRefreshToken,
};

export interface IssuedRefreshToken {
  token: string;
  hash: string;
  expiresAt: Date;
}

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function issueRefreshToken(now = new Date()): IssuedRefreshToken {
  const token = randomBytes(32).toString("base64url");
  return { token, hash: hashRefreshToken(token), expiresAt: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1_000) };
}

export async function rotateRefreshToken(
  token: string,
  userAgent: string | null,
  repository: RefreshTokenRepository = databaseRepository,
  now = new Date()
): Promise<RefreshTokenRecord & { refreshToken: string }> {
  const existing = await repository.findByHash(hashRefreshToken(token));
  if (!existing) throw new InvalidRefreshTokenError();
  if (existing.revokedAt) {
    await repository.revokeAllForUser(existing.userId);
    throw new RefreshTokenReuseError();
  }
  if (existing.expiresAt <= now) {
    await repository.revoke(existing.id);
    throw new InvalidRefreshTokenError();
  }
  await repository.revoke(existing.id);
  const next = issueRefreshToken(now);
  const saved = await repository.create({ userId: existing.userId, tokenHash: next.hash, expiresAt: next.expiresAt, userAgent });
  return { ...saved, refreshToken: next.token };
}
