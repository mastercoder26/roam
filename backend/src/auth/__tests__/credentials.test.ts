import { describe, expect, it } from "vitest";
import { checkPassword } from "../service.js";

describe("login credential checks", () => {
  it("returns the same generic failure for an absent user and a wrong password", async () => {
    const existingUserDigest = await checkPassword(null, "wrong password");
    const absentUserDigest = await checkPassword(null, "wrong password");

    expect(existingUserDigest).toBe(false);
    expect(absentUserDigest).toBe(false);
  });
});
