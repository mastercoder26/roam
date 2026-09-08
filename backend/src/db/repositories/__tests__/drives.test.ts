import { afterEach, describe, expect, it } from "vitest";
import type { PoolLike, QueryResult } from "../../pool.js";
import { setPoolForTests } from "../../pool.js";
import {
  aggregateDriveStats,
  getDrive,
  listDrives,
  softDeleteDrive,
  upsertDrives,
} from "../drives.js";
import { findOrCreateByClerkId, updateUserDisplayName } from "../users.js";

const userId = "00000000-0000-0000-0000-000000000001";
const driveId = "00000000-0000-0000-0000-000000000002";

function driveRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: driveId,
    user_id: userId,
    started_at: new Date("2026-01-02T03:04:05.000Z"),
    duration_seconds: 120,
    distance_meters: 1_500,
    score: 92,
    top_speed_meters_per_second: 20,
    event_count: 3,
    recording_time_zone_identifier: "America/Chicago",
    payload: { id: driveId },
    created_at: new Date("2026-01-02T03:05:05.000Z"),
    updated_at: new Date("2026-01-02T03:05:05.000Z"),
    ...overrides,
  };
}

function fakePool(query: (text: string, values?: readonly unknown[]) => Promise<QueryResult>): PoolLike {
  return {
    query: async <Row extends Record<string, unknown>>(text: string, values?: readonly unknown[]) => await query(text, values) as QueryResult<Row>,
    connect: async () => { throw new Error("not used"); },
    on: () => fakePool(query),
  };
}

afterEach(() => {
  setPoolForTests(null);
  delete process.env.DATABASE_URL;
});

describe("drive repository", () => {
  it("lists newest drives with a bounded keyset page", async () => {
    process.env.DATABASE_URL = "postgres://test";
    let queryText = "";
    let queryValues: readonly unknown[] = [];
    setPoolForTests(fakePool(async (text: string, values: readonly unknown[] | undefined): Promise<QueryResult> => {
      queryText = text;
      queryValues = values ?? [];
      return { rows: [driveRow()], rowCount: 1 };
    }));

    const result = await listDrives(userId, { limit: 500, before: new Date("2026-01-03T00:00:00.000Z") });

    expect(result).toHaveLength(1);
    expect(queryText).toContain("user_id = $1");
    expect(queryText).toContain("started_at < $2");
    expect(queryText).toContain("ORDER BY started_at DESC");
    expect(queryText).toContain("LIMIT $3");
    expect(queryValues).toEqual([userId, new Date("2026-01-03T00:00:00.000Z"), 200]);
  });

  it("keeps reads and deletes scoped to the authenticated user", async () => {
    process.env.DATABASE_URL = "postgres://test";
    const queries: Array<{ text: string; values: readonly unknown[] }> = [];
    setPoolForTests(fakePool(async (text: string, values: readonly unknown[] | undefined): Promise<QueryResult> => {
      queries.push({ text, values: values ?? [] });
      return { rows: [], rowCount: 0 };
    }));

    await expect(getDrive("00000000-0000-0000-0000-000000000003", driveId)).resolves.toBeNull();
    await expect(softDeleteDrive("00000000-0000-0000-0000-000000000003", driveId)).resolves.toBe(false);

    expect(queries).toHaveLength(2);
    for (const query of queries) {
      expect(query.text).toContain("user_id = $1");
      expect(query.values).toContain("00000000-0000-0000-0000-000000000003");
      expect(query.values).toContain(driveId);
    }
  });

  it("upserts a batch idempotently without allowing cross-user uuid takeover", async () => {
    process.env.DATABASE_URL = "postgres://test";
    let queryText = "";
    let queryValues: readonly unknown[] = [];
    setPoolForTests(fakePool(async (text: string, values: readonly unknown[] | undefined): Promise<QueryResult> => {
      queryText = text;
      queryValues = values ?? [];
      return { rows: [driveRow()], rowCount: 1 };
    }));

    const input = {
      id: driveId,
      startedAt: new Date("2026-01-02T03:04:05.000Z"),
      durationSeconds: 120,
      distanceMeters: 1_500,
      score: 92,
      topSpeedMetersPerSecond: 20,
      eventCount: 3,
      recordingTimeZoneIdentifier: "America/Chicago",
      payload: { id: driveId, route: [] },
    };
    await upsertDrives(userId, [input]);

    expect(queryText).toContain("ON CONFLICT (id) DO UPDATE");
    expect(queryText).toContain("WHERE drives.user_id = EXCLUDED.user_id");
    expect(queryText).toContain("deleted_at = NULL");
    expect(queryText).toContain("updated_at = now()");
    expect(queryValues).toContain(userId);
    expect(queryValues).toContain(JSON.stringify(input.payload));
    expect(queryText).not.toContain(JSON.stringify(input.payload));
  });

  it("deduplicates drives with duplicate IDs in a batch to avoid SQLSTATE 21000", async () => {
    process.env.DATABASE_URL = "postgres://test";
    let queryValues: readonly unknown[] = [];
    setPoolForTests(fakePool(async (_text: string, values: readonly unknown[] | undefined): Promise<QueryResult> => {
      queryValues = values ?? [];
      return { rows: [driveRow()], rowCount: 1 };
    }));

    const drive1 = {
      id: driveId,
      startedAt: new Date("2026-01-02T03:04:05.000Z"),
      durationSeconds: 120,
      distanceMeters: 1_500,
      score: 90,
      topSpeedMetersPerSecond: 20,
      eventCount: 3,
      recordingTimeZoneIdentifier: "America/Chicago",
      payload: { version: 1 },
    };
    const drive2 = {
      ...drive1,
      score: 95,
      payload: { version: 2 },
    };

    const results = await upsertDrives(userId, [drive1, drive2]);
    expect(results).toHaveLength(1);
    expect(queryValues).toHaveLength(10);
    expect(queryValues).toContain(JSON.stringify(drive2.payload));
  });

  it("returns aggregate progress statistics", async () => {
    process.env.DATABASE_URL = "postgres://test";
    setPoolForTests(fakePool(async (): Promise<QueryResult> => ({
      rows: [{ total_drives: "4", total_distance_meters: 4200.5, total_duration_seconds: 900, average_score: 87.5 }],
      rowCount: 1,
    })));

    await expect(aggregateDriveStats(userId)).resolves.toEqual({
      totalDrives: 4,
      totalDistanceMeters: 4200.5,
      totalDurationSeconds: 900,
      averageScore: 87.5,
    });
  });
});

describe("user repository optimizations (B9, B10)", () => {
  it("findOrCreateByClerkId reads existing user without issuing INSERT when claims match", async () => {
    process.env.DATABASE_URL = "postgres://test";
    const queries: string[] = [];
    setPoolForTests(fakePool(async (text: string): Promise<QueryResult> => {
      queries.push(text);
      return {
        rows: [{
          id: userId,
          clerk_user_id: "clerk_123",
          email: "driver@example.com",
          display_name: "Driver",
          created_at: new Date(),
          updated_at: new Date(),
          email_verified_at: null,
          deleted_at: null,
        }],
        rowCount: 1,
      };
    }));

    const user = await findOrCreateByClerkId({
      clerkUserId: "clerk_123",
      email: "driver@example.com",
      displayName: "Driver",
    });

    expect(user.id).toBe(userId);
    expect(queries).toHaveLength(1);
    expect(queries[0]).toContain("SELECT");
    expect(queries[0]).not.toContain("INSERT INTO users");
  });

  it("updateUserDisplayName updates display_name in users table", async () => {
    process.env.DATABASE_URL = "postgres://test";
    let queryText = "";
    let queryValues: readonly unknown[] = [];
    setPoolForTests(fakePool(async (text: string, values?: readonly unknown[]): Promise<QueryResult> => {
      queryText = text;
      queryValues = values ?? [];
      return { rows: [], rowCount: 1 };
    }));

    await updateUserDisplayName(userId, "New Name");
    expect(queryText).toContain("UPDATE users");
    expect(queryText).toContain("SET display_name = $2");
    expect(queryValues).toEqual([userId, "New Name"]);
  });
});

