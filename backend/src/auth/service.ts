import { isDatabaseConfigured } from "../db/pool.js";
import * as usersRepository from "../db/repositories/users.js";
import * as refreshRepository from "../db/repositories/refreshTokens.js";
import type { UserRecord, PublicUser } from "../db/types.js";
import { AuthConfigurationError, EmailTakenError, InvalidCredentialsError, InvalidRefreshTokenError } from "./errors.js";
import { hashPassword, verifyPassword, hashRefreshToken } from "./password.js";
import { issueAccessToken, ACCESS_TOKEN_TTL_SECONDS, hasJwtSecret } from "./tokens.js";
import { issueRefreshToken } from "./refresh.js";

export interface AuthSession { user: PublicUser; accessToken: string; refreshToken: string; expiresIn: number; }

export interface UserRepository {
  findByEmail(email: string): Promise<UserRecord | null>;
  findById(id: string): Promise<UserRecord | null>;
  create(input: { email: string; passwordHash: string; displayName: string | null }): Promise<UserRecord>;
  softDelete(id: string): Promise<void>;
}

export interface RefreshRepository {
  create(input: { userId: string; tokenHash: string; expiresAt: Date; userAgent: string | null }): Promise<refreshRepository.RefreshTokenRecord>;
  rotate(input: { tokenHash: string; nextTokenHash: string; expiresAt: Date; userAgent: string | null; now?: Date }): Promise<refreshRepository.RefreshRotationResult>;
  revoke(id: string): Promise<void>;
  revokeAllForUser(userId: string): Promise<void>;
  findByHash?: (tokenHash: string) => Promise<refreshRepository.RefreshTokenRecord | null>;
}

export interface AuthServiceDependencies { users: UserRepository; refreshTokens: RefreshRepository; jwtSecret?: string; }

export class AuthServiceError extends Error {
  constructor(readonly code: "UNAUTHORIZED" | "EMAIL_TAKEN" | "SERVICE_UNAVAILABLE" | "INTERNAL_ERROR", message: string, readonly status = code === "EMAIL_TAKEN" ? 409 : code === "UNAUTHORIZED" ? 401 : 503) {
    super(message);
    this.name = "AuthServiceError";
  }
}

function publicUser(user: UserRecord): PublicUser { return { id: user.id, email: user.email, displayName: user.displayName }; }
function secret(dependencies: AuthServiceDependencies): string {
  const value = dependencies.jwtSecret ?? process.env.JWT_SECRET;
  if (!value) throw new AuthConfigurationError("JWT_SECRET is not configured.");
  return value;
}
function expiresAt(now: Date): Date { return new Date(now.getTime() + 30 * 24 * 60 * 60 * 1_000); }
function unique(error: unknown): boolean {
  return usersRepository.isUniqueViolation(error) || (typeof error === "object" && error !== null && (error as { code?: unknown }).code === "23505");
}

export async function checkPassword(passwordHash: string | null, password: string): Promise<boolean> {
  if (!passwordHash) { await hashPassword(password); return false; }
  return verifyPassword(passwordHash, password);
}

function makeService(dependencies: AuthServiceDependencies) {
  return {
    async signup(email: string, password: string, displayName: string | null, userAgent: string | null = null): Promise<AuthSession> {
      const digest = await hashPassword(password);
      let user: UserRecord;
      try { user = await dependencies.users.create({ email, passwordHash: digest, displayName }); }
      catch (error) { if (unique(error)) throw new AuthServiceError("EMAIL_TAKEN", "An account with that email already exists.", 409); throw error; }
      const refresh = issueRefreshToken();
      await dependencies.refreshTokens.create({ userId: user.id, tokenHash: refresh.hash, expiresAt: refresh.expiresAt, userAgent });
      return { user: publicUser(user), accessToken: issueAccessToken(user, secret(dependencies)), refreshToken: refresh.token, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
    },
    async login(email: string, password: string, userAgent: string | null = null): Promise<AuthSession> {
      const user = await dependencies.users.findByEmail(email);
      const valid = await checkPassword(user?.passwordHash ?? null, password);
      if (!user || !valid) throw new AuthServiceError("UNAUTHORIZED", "Invalid email or password.", 401);
      const refresh = issueRefreshToken();
      await dependencies.refreshTokens.create({ userId: user.id, tokenHash: refresh.hash, expiresAt: refresh.expiresAt, userAgent });
      return { user: publicUser(user), accessToken: issueAccessToken(user, secret(dependencies)), refreshToken: refresh.token, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
    },
    async refresh(token: string, userAgent: string | null = null, now = new Date()) {
      const next = issueRefreshToken(now);
      const result = await dependencies.refreshTokens.rotate({ tokenHash: hashRefreshToken(token), nextTokenHash: next.hash, expiresAt: next.expiresAt, userAgent, now });
      if (result.status !== "rotated") throw new AuthServiceError("UNAUTHORIZED", "Invalid refresh token.", 401);
      const user = await dependencies.users.findById(result.userId);
      if (!user) throw new InvalidRefreshTokenError();
      return { accessToken: issueAccessToken(user, secret(dependencies), now.getTime()), refreshToken: next.token, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
    },
    async logout(token: string): Promise<void> { const record = dependencies.refreshTokens.findByHash ? await dependencies.refreshTokens.findByHash(hashRefreshToken(token)) : null; if (record) await dependencies.refreshTokens.revoke(record.id); },
    async deleteAccount(id: string): Promise<void> { await dependencies.refreshTokens.revokeAllForUser(id); await dependencies.users.softDelete(id); },
    async getUser(id: string): Promise<UserRecord | null> { return dependencies.users.findById(id); },
  };
}

export function createAuthService(dependencies: AuthServiceDependencies) { return makeService(dependencies); }

export function assertAuthConfigured(): void {
  if (!hasJwtSecret() || !isDatabaseConfigured()) throw new AuthConfigurationError("Account services are not configured.");
}

const dependencies: AuthServiceDependencies = {
  users: { findByEmail: usersRepository.findByEmail, findById: usersRepository.findById, create: usersRepository.create, softDelete: usersRepository.softDelete },
  refreshTokens: { create: refreshRepository.create, rotate: refreshRepository.rotate, revoke: refreshRepository.revoke, revokeAllForUser: refreshRepository.revokeAllForUser, findByHash: refreshRepository.findByHash },
};
export const defaultAuthService = makeService(dependencies);

export async function signup(input: { email: string; password: string; displayName?: string }, userAgent: string | null): Promise<AuthSession> { assertAuthConfigured(); return defaultAuthService.signup(input.email, input.password, input.displayName ?? null, userAgent); }
export async function login(input: { email: string; password: string }, userAgent: string | null): Promise<AuthSession> { assertAuthConfigured(); return defaultAuthService.login(input.email, input.password, userAgent); }
export async function refreshSession(token: string, userAgent: string | null) { assertAuthConfigured(); return defaultAuthService.refresh(token, userAgent); }
export async function logout(token: string) { assertAuthConfigured(); return defaultAuthService.logout(token); }
export async function getCurrentUser(id: string): Promise<PublicUser> { assertAuthConfigured(); const user = await defaultAuthService.getUser(id); if (!user) throw new InvalidCredentialsError(); return publicUser(user); }
export async function deleteAccount(id: string) { assertAuthConfigured(); return defaultAuthService.deleteAccount(id); }
