import { describe, expect, it } from "vitest";
import { assessScoreEvidence } from "../certainty.js";

describe("score evidence coverage", () => {
  it("describes complete verified inputs without claiming predictive validation", () => {
    const evidence = assessScoreEvidence({
      hasValidatedGeometry: true,
      trafficTimingAvailable: true,
      speedLimitCoverage: 1,
      weatherAvailable: true,
      roadAvailable: true,
      turnControlsAvailable: true,
    });

    expect(evidence.inputCoverage).toBe(1);
    expect(evidence.level).toBe("wellSupported");
    expect(evidence.predictiveValidation).toBe("notValidated");
    expect(evidence.missingSignals).toEqual([]);
    expect("predictionInterval" in evidence).toBe(false);
  });

  it("names unavailable live signals without turning coverage into a prediction interval", () => {
    const complete = assessScoreEvidence({
      hasValidatedGeometry: true,
      trafficTimingAvailable: true,
      speedLimitCoverage: 1,
      weatherAvailable: true,
      roadAvailable: true,
      turnControlsAvailable: true,
    });
    const partial = assessScoreEvidence({
      hasValidatedGeometry: true,
      trafficTimingAvailable: true,
      speedLimitCoverage: 0,
      weatherAvailable: false,
      roadAvailable: false,
      turnControlsAvailable: false,
    });

    expect(partial.level).toBe("limited");
    expect(partial.inputCoverage).toBeLessThan(complete.inputCoverage);
    expect(partial.missingSignals).toEqual(
      expect.arrayContaining(["speedLimits", "weather", "roadMetadata", "turnControls"])
    );
  });

  it("treats posted-speed coverage as a fractional verified input", () => {
    const halfCovered = assessScoreEvidence({
      hasValidatedGeometry: true,
      trafficTimingAvailable: true,
      speedLimitCoverage: 0.5,
      weatherAvailable: true,
      roadAvailable: true,
      turnControlsAvailable: true,
    });
    const fullCovered = assessScoreEvidence({
      hasValidatedGeometry: true,
      trafficTimingAvailable: true,
      speedLimitCoverage: 1,
      weatherAvailable: true,
      roadAvailable: true,
      turnControlsAvailable: true,
    });

    expect(halfCovered.inputCoverage).toBeLessThan(fullCovered.inputCoverage);
    expect(halfCovered.verifiedSignals).toContain("speedLimits");
  });
});
