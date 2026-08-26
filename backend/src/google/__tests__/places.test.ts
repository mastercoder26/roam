import { afterEach, describe, expect, it, vi } from "vitest";
import { autocompleteAddresses } from "../places.js";

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
