import { describe, expect, it } from "vitest";
import {
  hashRefreshToken,
  issueRefreshToken,
  rotateRefreshToken,
  RefreshTokenReuseError,
  type RefreshTokenRepository,
} from "../refresh.js";
import type { RefreshTokenRecord } from "../../db/repositories/refreshTokens.js";

describe("refresh tokens", () => {
  it("issues opaque tokens and stores only their hash", () => {
    const first = issueRefreshToken();
    const second = issueRefreshToken();

    expect(first.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(first.token).not.toBe(second.token);
    expect(first.hash).toBe(hashRefreshToken(first.token));
    expect(first.hash).not.toContain(first.token);
  });

  it("rotates once and revokes all user tokens when the old token is reused", async () => {
    const issued = issueRefreshToken();
    let stored: RefreshTokenRecord = {
      id: "refresh-1",
      userId: "user-1",
      tokenHash: issued.hash,
      expiresAt: new Date(Date.now() + 86_400_000),
      revokedAt: null,
      createdAt: new Date(),
      userAgent: null,
    };
    let revokeAllCalls = 0;
    const repository: RefreshTokenRepository = {
      findByHash: async () => stored,
      revoke: async () => {
        stored = { ...stored, revokedAt: new Date() };
      },
      revokeAllForUser: async () => {
        revokeAllCalls += 1;
      },
      create: async (input) => ({
        ...input,
        id: "refresh-2",
        createdAt: new Date(),
        revokedAt: null,
      }),
    };

    await expect(rotateRefreshToken(issued.token, "test-agent", repository)).resolves.toMatchObject({
      userId: "user-1",
    });
    await expect(rotateRefreshToken(issued.token, "test-agent", repository))
      .rejects.toBeInstanceOf(RefreshTokenReuseError);
    expect(revokeAllCalls).toBe(1);
  });
});
