import type { Request, Response } from "express";
import { afterEach, describe, expect, it } from "vitest";
import { handleUpdateProfile, validateProfileUpdate } from "../profile.js";
import { setPoolForTests, type PoolLike, type QueryResult } from "../../db/pool.js";

function responseDouble() {
  const res = {
    statusCode: 200,
    body: undefined as unknown,
    status(code: number) {
      res.statusCode = code;
      return res;
    },
    json(body: unknown) {
      res.body = body;
      return res;
    },
  };
  return res;
}

function fakePool(query: (text: string, values?: readonly unknown[]) => Promise<QueryResult>): PoolLike {
  return {
    query: async <Row extends Record<string, unknown>>(text: string, values?: readonly unknown[]) => await query(text, values) as QueryResult<Row>,
    connect: async () => { throw new Error("not used"); },
    on: () => fakePool(query),
  };
}

describe("profile validation", () => {
  it("accepts partial last-write-wins updates", () => {
    expect(validateProfileUpdate({
      stage: "licensed",
      payload: { preferredTheme: "dark" },
    })).toEqual({
      stage: "licensed",
      payload: { preferredTheme: "dark" },
    });
  });

  it("rejects invalid stages and non-object payloads", () => {
    expect(() => validateProfileUpdate({ stage: "expert" })).toThrow();
    expect(() => validateProfileUpdate({ payload: "not-json" })).toThrow();
  });
});

describe("handleUpdateProfile display name sync (B10)", () => {
  afterEach(() => {
    setPoolForTests(null);
    delete process.env.DATABASE_URL;
  });

  it("synchronizes displayName to users when updated in profile", async () => {
    process.env.DATABASE_URL = "postgres://test";
    const queries: Array<{ text: string; values?: readonly unknown[] }> = [];
    setPoolForTests(fakePool(async (text: string, values?: readonly unknown[]): Promise<QueryResult> => {
      queries.push({ text, values });
      return {
        rows: [{
          user_id: "00000000-0000-0000-0000-000000000001",
          display_name: "Updated Name",
          stage: "licensed",
          payload: {},
          updated_at: new Date("2026-01-01T00:00:00.000Z"),
        }],
        rowCount: 1,
      };
    }));

    const res = responseDouble();
    const req = {
      body: { displayName: "Updated Name", stage: "licensed" },
      user: { id: "00000000-0000-0000-0000-000000000001" },
    } as unknown as Request;

    await handleUpdateProfile(req, res as unknown as Response);

    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({
      profile: { displayName: "Updated Name", stage: "licensed" },
    });

    const userUpdate = queries.find((q) => q.text.includes("UPDATE users"));
    expect(userUpdate).toBeDefined();
    expect(userUpdate?.values).toEqual(["00000000-0000-0000-0000-000000000001", "Updated Name"]);

    const profileUpdate = queries.find((q) => q.text.includes("driver_profiles"));
    expect(profileUpdate).toBeDefined();
  });
});

