import { describe, expect, it } from "vitest";
import { hashPassword, verifyPassword } from "../password.js";

describe("password hashing", () => {
  it("hashes and verifies a password without storing the cleartext", async () => {
    const password = "A secure test password 123!";
    const hash = await hashPassword(password);

    expect(hash).not.toContain(password);
    expect(await verifyPassword(hash, password)).toBe(true);
    expect(await verifyPassword(hash, "different password")).toBe(false);
  });
});
