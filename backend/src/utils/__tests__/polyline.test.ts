import { describe, expect, it } from "vitest";
import { decodePolyline, samplePolylinePoints } from "../polyline.js";

describe("polyline utilities", () => {
  it("decodes a known encoded polyline", () => {
    const points = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
    expect(points.length).toBeGreaterThan(1);
    expect(points[0]).toHaveProperty("lat");
    expect(points[0]).toHaveProperty("lng");
  });

  it("samples evenly spaced points up to target count", () => {
    const encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@";
    const decoded = decodePolyline(encoded);
    const sampled = samplePolylinePoints(encoded, 10);
    expect(sampled.length).toBe(Math.min(decoded.length, 10));
    expect(sampled.length).toBeGreaterThan(0);
  });
});
