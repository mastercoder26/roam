import type { Request, Response } from "express";
import { describe, expect, it } from "vitest";
import { handleSignup } from "../auth.js";

function responseDouble() {
  const response = {
    statusCode: 200,
    status(code: number) {
      response.statusCode = code;
      return response;
    },
    jsonBody: undefined as unknown,
    json(body: unknown) {
      response.jsonBody = body;
      return response;
    },
    end() {
      return response;
    },
  };
  return response;
}

describe("auth handlers", () => {
  it("returns a service-unavailable envelope when the database is unconfigured", async () => {
    const previousDatabaseUrl = process.env.DATABASE_URL;
    const previousJwtSecret = process.env.JWT_SECRET;
    delete process.env.DATABASE_URL;
    process.env.JWT_SECRET = "test-secret";
    const response = responseDouble();

    try {
      await handleSignup(
        { body: { email: "driver@example.com", password: "correct password" } } as Request,
        response as unknown as Response
      );
      expect(response.statusCode).toBe(503);
      expect(response.jsonBody).toEqual({
        error: "Account services are temporarily unavailable. Please try again shortly.",
        code: "SERVICE_UNAVAILABLE",
        requestId: expect.any(String),
      });
    } finally {
      if (previousDatabaseUrl === undefined) delete process.env.DATABASE_URL;
      else process.env.DATABASE_URL = previousDatabaseUrl;
      if (previousJwtSecret === undefined) delete process.env.JWT_SECRET;
      else process.env.JWT_SECRET = previousJwtSecret;
    }
  });

  it("rejects malformed signup input at the boundary", async () => {
    const response = responseDouble();
    await handleSignup(
      { body: { email: "not-an-email", password: "short" } } as Request,
      response as unknown as Response
    );

    expect(response.statusCode).toBe(400);
    expect(response.jsonBody).toMatchObject({ code: "VALIDATION_ERROR" });
  });
});
