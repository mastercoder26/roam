import { getPool, withTransaction } from "../pool.js";
import type { QueryResult } from "../pool.js";
import { queryDatabase } from "./helpers.js";

export interface RefreshTokenRecord {
  id: string;
  userId: string;
  tokenHash: string;
  expiresAt: Date;
  revokedAt: Date | null;
  createdAt: Date;
  userAgent: string | null;
}

interface RefreshTokenRow extends Record<string, unknown> {
  id: string;
  user_id: string;
  token_hash: string;
  expires_at: Date;
  revoked_at: Date | null;
  created_at: Date;
  user_agent: string | null;
}

function mapRefreshToken(row: RefreshTokenRow): RefreshTokenRecord {
  return { id: row.id, userId: row.user_id, tokenHash: row.token_hash, expiresAt: new Date(row.expires_at), revokedAt: row.revoked_at ? new Date(row.revoked_at) : null, createdAt: new Date(row.created_at), userAgent: row.user_agent };
}

export async function findRefreshTokenByHash(hash: string): Promise<RefreshTokenRecord | null> {
  const result: QueryResult<RefreshTokenRow> = await queryDatabase<RefreshTokenRow>(getPool(), `
    SELECT id, user_id, token_hash, expires_at, revoked_at, created_at, user_agent
    FROM refresh_tokens WHERE token_hash = $1 LIMIT 1
  `, [hash]);
  const row = result.rows[0];
  return row ? mapRefreshToken(row) : null;
}

export async function createRefreshToken(input: {
  userId: string;
  tokenHash: string;
  expiresAt: Date;
  userAgent: string | null;
}): Promise<RefreshTokenRecord> {
  const result = await queryDatabase<RefreshTokenRow>(getPool(), `
    INSERT INTO refresh_tokens (user_id, token_hash, expires_at, user_agent)
    VALUES ($1, $2, $3, $4)
    RETURNING id, user_id, token_hash, expires_at, revoked_at, created_at, user_agent
  `, [input.userId, input.tokenHash, input.expiresAt, input.userAgent]);
  const row = result.rows[0];
  if (!row) throw new Error("Refresh token insert returned no row");
  return mapRefreshToken(row);
}

export async function revokeRefreshToken(id: string): Promise<void> {
  await queryDatabase(getPool(), "UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE id = $1", [id]);
}

export async function revokeAllRefreshTokens(userId: string): Promise<void> {
  await queryDatabase(getPool(), "UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1 AND revoked_at IS NULL", [userId]);
}

export type RefreshRotationResult =
  | { status: "rotated"; userId: string }
  | { status: "invalid" }
  | { status: "reused"; userId: string };

export async function rotate(input: {
  tokenHash: string;
  nextTokenHash: string;
  expiresAt: Date;
  userAgent: string | null;
  now?: Date;
}): Promise<RefreshRotationResult> {
  return withTransaction(async (client) => {
    const result = await client.query<RefreshTokenRow>(
      `SELECT id, user_id, token_hash, expires_at, revoked_at, created_at, user_agent
       FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
      [input.tokenHash]
    );
    const row = result.rows[0];
    if (!row) return { status: "invalid" };
    const token = mapRefreshToken(row);
    if (token.revokedAt) {
      await client.query("UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1 AND revoked_at IS NULL", [token.userId]);
      return { status: "reused", userId: token.userId };
    }
    if (token.expiresAt <= (input.now ?? new Date())) return { status: "invalid" };
    await client.query("UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1", [token.id]);
    await client.query("INSERT INTO refresh_tokens (user_id, token_hash, expires_at, user_agent) VALUES ($1, $2, $3, $4)", [token.userId, input.nextTokenHash, input.expiresAt, input.userAgent]);
    return { status: "rotated", userId: token.userId };
  });
}

export const findByHash = findRefreshTokenByHash;
export const create = createRefreshToken;
export const revoke = revokeRefreshToken;
export const revokeAllForUser = revokeAllRefreshTokens;
