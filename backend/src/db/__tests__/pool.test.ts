import { describe, expect, it } from "vitest";
import { DatabaseUnavailableError } from "../../errors.js";
import { getPool, isDatabaseConfigured } from "../pool.js";

describe("database configuration", () => {
  it("reports an unconfigured database and throws a typed error lazily", () => {
    const previousDatabaseUrl = process.env.DATABASE_URL;
    delete process.env.DATABASE_URL;

    try {
      expect(isDatabaseConfigured()).toBe(false);
      expect(() => getPool()).toThrow(DatabaseUnavailableError);
    } finally {
      if (previousDatabaseUrl === undefined) delete process.env.DATABASE_URL;
      else process.env.DATABASE_URL = previousDatabaseUrl;
    }
  });
});
