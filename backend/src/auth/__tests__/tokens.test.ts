import { describe, expect, it } from "vitest";
import {
  issueAccessToken,
  verifyAccessToken,
  type AuthTokenUser,
} from "../tokens.js";

const user: AuthTokenUser = {
  id: "00000000-0000-0000-0000-000000000001",
  email: "driver@example.com",
};

describe("access tokens", () => {
  it("issues and verifies a short-lived HS256 token", () => {
    const token = issueAccessToken(user, "test-secret", 1_700_000_000_000);
    expect(verifyAccessToken(token, "test-secret", 1_700_000_000_500)).toEqual(user);
  });

  it("distinguishes an expired token from an invalid token", () => {
    const token = issueAccessToken(user, "test-secret", 1_700_000_000_000, -1);

    expect(() => verifyAccessToken(token, "test-secret", 1_700_000_001_000)).toThrowError(
      expect.objectContaining({ code: "TOKEN_EXPIRED" })
    );
    expect(() => verifyAccessToken(`${token}broken`, "test-secret")).toThrowError(
      expect.objectContaining({ code: "UNAUTHORIZED" })
    );
  });
});
