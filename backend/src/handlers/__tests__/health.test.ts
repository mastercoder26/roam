import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { app } from "../../../server.js";
import { setPoolForTests, type PoolLike, type QueryResult } from "../../db/pool.js";

const originalDatabaseUrl = process.env.DATABASE_URL;

function poolWithQuery(query: () => Promise<QueryResult>): PoolLike {
  return {
    query: async <Row extends Record<string, unknown>>() => await query() as QueryResult<Row>,
    connect: async () => { throw new Error("not used"); },
    on: () => poolWithQuery(query),
  };
}

describe("GET /health", () => {
  let server: Server;
  let url: string;

  beforeEach(async () => {
    await new Promise<void>((resolve) => {
      server = app.listen(0, () => {
        url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/health`;
        resolve();
      });
    });
  });

  afterEach(async () => {
    setPoolForTests(null);
    if (originalDatabaseUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = originalDatabaseUrl;
    vi.restoreAllMocks();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it("stays healthy when this deployment has no database configured", async () => {
    delete process.env.DATABASE_URL;

    const response = await fetch(url);

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: "degraded", database: "unconfigured" });
  });

  it("returns 503 when a configured database is down", async () => {
    process.env.DATABASE_URL = "postgres://test";
    setPoolForTests(poolWithQuery(async () => { throw new Error("database down"); }));
    vi.spyOn(console, "error").mockImplementation(() => {});

    const response = await fetch(url);

    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ status: "degraded", database: "down" });
  });

  it("returns 200 when a configured database responds", async () => {
    process.env.DATABASE_URL = "postgres://test";
    setPoolForTests(poolWithQuery(async () => ({ rows: [{ '?column?': 1 }], rowCount: 1 })));

    const response = await fetch(url);

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: "ok", database: "up" });
  });
});
