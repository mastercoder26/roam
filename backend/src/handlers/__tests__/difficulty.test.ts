import { describe, expect, it } from "vitest";
import { validateDifficultyRequest } from "../difficulty.js";

describe("difficulty request validation", () => {
  it("accepts a client-local departure clock", () => {
    expect(
      validateDifficultyRequest({
        origin: "A",
        destination: "B",
        departureLocalMinutes: 22 * 60 + 15,
      })
    ).toMatchObject({ departureLocalMinutes: 1335 });
  });

  it("rejects an invalid client-local departure clock", () => {
    expect(() =>
      validateDifficultyRequest({
        origin: "A",
        destination: "B",
        departureLocalMinutes: 24 * 60,
      })
    ).toThrow("departureLocalMinutes must be an integer between 0 and 1439");
  });
});
