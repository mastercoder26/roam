import type { Request, Response } from "express";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { app } from "../../../server.js";
import { ClerkAccountDeletionError } from "../../auth/errors.js";
import { DatabaseOperationError } from "../../errors.js";

const { deleteClerkUserMock, deleteUserMock, findByIdMock, toPublicUserMock } = vi.hoisted(() => ({
  deleteClerkUserMock: vi.fn(),
  deleteUserMock: vi.fn(),
  findByIdMock: vi.fn(),
  toPublicUserMock: vi.fn(),
}));

vi.mock("../../auth/client.js", () => ({ deleteClerkUser: deleteClerkUserMock }));
vi.mock("../../db/repositories/users.js", () => ({
  deleteUser: deleteUserMock,
  findById: findByIdMock,
  toPublicUser: toPublicUserMock,
}));

import { handleDeleteAccount, handleMe } from "../auth.js";

function responseDouble() {
  const response = {
    statusCode: 200,
    body: undefined as unknown,
    status(code: number) {
      response.statusCode = code;
      return response;
    },
    json(body: unknown) {
      response.body = body;
      return response;
    },
    end() {
      return response;
    },
  };
  return response as unknown as Response & { statusCode: number; body: unknown };
}

const request = {
  user: {
    id: "00000000-0000-0000-0000-000000000001",
    email: "driver@example.com",
    clerkUserId: "user_clerk_123",
  },
} as unknown as Request;

describe("Clerk-backed account handlers", () => {
  beforeEach(() => {
    deleteClerkUserMock.mockReset();
    deleteUserMock.mockReset();
  });

  it("keeps the Clerk identity when the local deletion fails so the user can retry", async () => {
    deleteUserMock.mockRejectedValueOnce(new DatabaseOperationError(new Error("db down")));
    const response = responseDouble();

    await handleDeleteAccount(request, response);

    expect(response.statusCode).toBe(503);
    expect(response.body).toMatchObject({ code: "SERVICE_UNAVAILABLE" });
    expect(deleteClerkUserMock).not.toHaveBeenCalled();
  });

  it("reports a retryable failure when Clerk deletion fails after local data is gone", async () => {
    deleteUserMock.mockResolvedValueOnce(undefined);
    deleteClerkUserMock.mockRejectedValueOnce(new ClerkAccountDeletionError(new Error("Clerk unavailable")));
    const response = responseDouble();

    await handleDeleteAccount(request, response);

    expect(response.statusCode).toBe(503);
    expect(response.body).toMatchObject({ code: "SERVICE_UNAVAILABLE" });
    expect(deleteUserMock).toHaveBeenCalledWith(request.user?.id);
  });

  it("deletes local personal data first, then the Clerk identity", async () => {
    deleteClerkUserMock.mockResolvedValueOnce(undefined);
    deleteUserMock.mockResolvedValueOnce(undefined);
    const response = responseDouble();

    await handleDeleteAccount(request, response);

    expect(response.statusCode).toBe(204);
    expect(deleteClerkUserMock).toHaveBeenCalledWith("user_clerk_123");
    expect(deleteUserMock).toHaveBeenCalledWith(request.user?.id);
    expect(deleteUserMock.mock.invocationCallOrder[0]).toBeLessThan(deleteClerkUserMock.mock.invocationCallOrder[0]);
  });

  it("returns the local user for /api/auth/me", async () => {
    const localUser = { id: request.user?.id, email: "driver@example.com" };
    findByIdMock.mockResolvedValueOnce(localUser);
    toPublicUserMock.mockReturnValueOnce({ id: localUser.id, email: localUser.email, displayName: null });
    const response = responseDouble();

    await handleMe(request, response);

    expect(response.statusCode).toBe(200);
    expect(response.body).toEqual({
      user: { id: localUser.id, email: localUser.email, displayName: null },
    });
  });
});

describe("server middleware (B11, B12)", () => {
  let server: Server;
  let port: number;

  beforeEach(async () => {
    await new Promise<void>((resolve) => {
      server = app.listen(0, () => {
        port = (server.address() as AddressInfo).port;
        resolve();
      });
    });
  });

  afterEach(async () => {
    await new Promise<void>((resolve) => {
      server.close(() => resolve());
    });
  });

  it("maps body-parser 413 error to HTTP 413 PAYLOAD_TOO_LARGE (B11)", async () => {
    const hugePayload = JSON.stringify({ padding: "a".repeat(2.5 * 1024 * 1024) });
    const res = await fetch(`http://127.0.0.1:${port}/api/route/difficulty`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: hugePayload,
    });

    expect(res.status).toBe(413);
    const body = await res.json();
    expect(body).toMatchObject({
      error: "Payload too large. Request body exceeds limit.",
      code: "PAYLOAD_TOO_LARGE",
      requestId: expect.any(String),
    });
  });

  it("emits Vary: Origin on dynamic CORS responses (B12)", async () => {
    const prevOrigins = process.env.ALLOWED_ORIGINS;
    process.env.ALLOWED_ORIGINS = "https://roam.example.com,http://localhost:3000";

    try {
      const res = await fetch(`http://127.0.0.1:${port}/health`, {
        headers: { Origin: "http://localhost:3000" },
      });

      expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:3000");
      expect(res.headers.get("vary")).toBe("Origin");
    } finally {
      if (prevOrigins === undefined) delete process.env.ALLOWED_ORIGINS;
      else process.env.ALLOWED_ORIGINS = prevOrigins;
    }
  });
});
