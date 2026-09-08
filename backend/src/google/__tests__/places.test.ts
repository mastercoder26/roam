import { afterEach, describe, expect, it, vi } from "vitest";
import type { Request, Response } from "express";
import { autocompleteAddresses } from "../places.js";
import { handleAddressAutocomplete } from "../../handlers/places.js";

function responseDouble() {
  const res = {
    statusCode: 200,
    headers: {} as Record<string, string>,
    body: undefined as unknown,
    status(code: number) {
      res.statusCode = code;
      return res;
    },
    setHeader(name: string, value: string) {
      res.headers[name.toLowerCase()] = value;
      return res;
    },
    json(body: unknown) {
      res.body = body;
      return res;
    },
  };
  return res as unknown as Response & { statusCode: number; headers: Record<string, string>; body: any };
}

describe("autocompleteAddresses", () => {
  afterEach(() => vi.restoreAllMocks());

  it("returns formatted place predictions and ignores query predictions", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({
      suggestions: [
        { placePrediction: { placeId: "one", text: { text: "1600 Amphitheatre Parkway, Mountain View, CA" } } },
        { queryPrediction: { text: { text: "1600 amphitheatre" } } },
      ],
    }), { status: 200 }));

    await expect(autocompleteAddresses("1600 Amph", "test-key")).resolves.toEqual([
      { placeId: "one", label: "1600 Amphitheatre Parkway, Mountain View, CA" },
    ]);

    expect(fetchMock).toHaveBeenCalledWith(
      "https://places.googleapis.com/v1/places:autocomplete",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({ "X-Goog-Api-Key": "test-key" }),
        body: JSON.stringify({ input: "1600 Amph", includeQueryPredictions: false }),
      })
    );
  });

  it("rejects upstream failures", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("{}", { status: 403 }));
    await expect(autocompleteAddresses("1600 Amph", "test-key")).rejects.toThrow("HTTP 403");
  });
});

describe("handleAddressAutocomplete", () => {
  const originalKey = process.env.GOOGLE_MAPS_API_KEY;

  afterEach(() => {
    vi.restoreAllMocks();
    if (originalKey !== undefined) process.env.GOOGLE_MAPS_API_KEY = originalKey;
    else delete process.env.GOOGLE_MAPS_API_KEY;
  });

  it("returns 400 with requestId when input is fewer than 3 characters", async () => {
    const res = responseDouble();
    const req = { query: { input: "ab" } } as unknown as Request;

    await handleAddressAutocomplete(req, res);

    expect(res.statusCode).toBe(400);
    expect(res.body).toMatchObject({
      error: "Enter at least 3 characters to search for an address.",
      code: "INVALID_REQUEST",
      requestId: expect.any(String),
    });
  });

  it("returns 503 with requestId when GOOGLE_MAPS_API_KEY is not configured", async () => {
    delete process.env.GOOGLE_MAPS_API_KEY;
    const res = responseDouble();
    const req = { query: { input: "1600 Amph" } } as unknown as Request;

    await handleAddressAutocomplete(req, res);

    expect(res.statusCode).toBe(503);
    expect(res.body).toMatchObject({
      error: "Address suggestions are temporarily unavailable.",
      code: "SERVICE_UNAVAILABLE",
      requestId: expect.any(String),
    });
  });

  it("returns 503 with requestId and logs failure when upstream fails", async () => {
    process.env.GOOGLE_MAPS_API_KEY = "test-api-key";
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("API network failure"));
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    const res = responseDouble();
    const req = { query: { input: "1600 Amph" } } as unknown as Request;

    await handleAddressAutocomplete(req, res);

    expect(res.statusCode).toBe(503);
    expect(res.body).toMatchObject({
      error: "Address suggestions are temporarily unavailable.",
      code: "SERVICE_UNAVAILABLE",
      requestId: expect.any(String),
    });
    expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining("places-autocomplete"));
  });
});

