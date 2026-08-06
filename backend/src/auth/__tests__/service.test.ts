import { describe, expect, it, vi } from "vitest";
import { hashPassword } from "../password.js";
import { createAuthService, type AuthServiceDependencies } from "../service.js";
import type { UserRecord } from "../../db/repositories/users.js";

const user: UserRecord = {
  id: "00000000-0000-0000-0000-000000000001",
  email: "driver@example.com",
  passwordHash: "",
  displayName: "Driver",
  createdAt: new Date("2026-01-01T00:00:00.000Z"),
  updatedAt: new Date("2026-01-01T00:00:00.000Z"),
  emailVerifiedAt: null,
};

function makeDependencies(overrides: Partial<AuthServiceDependencies> = {}): AuthServiceDependencies {
  return {
    users: {
      findByEmail: vi.fn(),
      findById: vi.fn(),
      create: vi.fn(),
      softDelete: vi.fn(),
    },
    refreshTokens: {
      create: vi.fn(),
      rotate: vi.fn(),
      revoke: vi.fn(),
      revokeAllForUser: vi.fn(),
    },
    jwtSecret: "test-secret",
    ...overrides,
  };
}

describe("authentication service", () => {
  it("uses the same public login failure for a missing email and a wrong password", async () => {
    const passwordHash = await hashPassword("correct password");
    const missingUserDependencies = makeDependencies();
    const wrongPasswordDependencies = makeDependencies({
      users: {
        ...makeDependencies().users,
        findByEmail: vi.fn().mockResolvedValue({ ...user, passwordHash }),
      },
    });
    const missingUserService = createAuthService(missingUserDependencies);
    const wrongPasswordService = createAuthService(wrongPasswordDependencies);

    await expect(missingUserService.login("driver@example.com", "wrong password")).rejects.toMatchObject({
      code: "UNAUTHORIZED",
      message: "Invalid email or password.",
    });
    await expect(wrongPasswordService.login("driver@example.com", "wrong password")).rejects.toMatchObject({
      code: "UNAUTHORIZED",
      message: "Invalid email or password.",
    });
  });

  it("rotates a refresh token and rejects reuse", async () => {
    const dependencies = makeDependencies({
      users: {
        ...makeDependencies().users,
        findById: vi.fn().mockResolvedValue(user),
      },
      refreshTokens: {
        ...makeDependencies().refreshTokens,
        rotate: vi.fn()
          .mockResolvedValueOnce({ status: "rotated", userId: user.id })
          .mockResolvedValueOnce({ status: "reused", userId: user.id }),
      },
    });
    const service = createAuthService(dependencies);

    const rotated = await service.refresh("old-refresh-token", "test-agent");
    expect(rotated.accessToken).toBeTypeOf("string");
    expect(rotated.refreshToken).toBeTypeOf("string");
    expect(dependencies.refreshTokens.rotate).toHaveBeenCalledTimes(1);

    await expect(service.refresh("old-refresh-token", "test-agent")).rejects.toMatchObject({
      code: "UNAUTHORIZED",
    });
  });
});
