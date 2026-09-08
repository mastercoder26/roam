import { describe, expect, it } from "vitest";
import { createRateLimiter } from "../rateLimiter.js";

describe("createRateLimiter", () => {
  it("allows requests up to the configured maximum within the window", () => {
    const limiter = createRateLimiter({ windowMs: 1_000, maxRequests: 3 });
    const now = 0;

    expect(limiter.check("client-a", now).allowed).toBe(true);
    expect(limiter.check("client-a", now).allowed).toBe(true);
    expect(limiter.check("client-a", now).allowed).toBe(true);
    expect(limiter.check("client-a", now).allowed).toBe(false);
  });

  it("reports a positive retry-after when blocked", () => {
    const limiter = createRateLimiter({ windowMs: 1_000, maxRequests: 1 });
    limiter.check("client-a", 0);

    const result = limiter.check("client-a", 400);
    expect(result.allowed).toBe(false);
    expect(result.retryAfterSeconds).toBeGreaterThan(0);
    expect(result.retryAfterSeconds).toBeLessThanOrEqual(1);
  });

  it("allows requests again once the window slides past the earliest hit", () => {
    const limiter = createRateLimiter({ windowMs: 1_000, maxRequests: 1 });
    limiter.check("client-a", 0);
    expect(limiter.check("client-a", 500).allowed).toBe(false);
    expect(limiter.check("client-a", 1_001).allowed).toBe(true);
  });

  it("tracks separate keys independently", () => {
    const limiter = createRateLimiter({ windowMs: 1_000, maxRequests: 1 });
    limiter.check("client-a", 0);

    expect(limiter.check("client-a", 0).allowed).toBe(false);
    expect(limiter.check("client-b", 0).allowed).toBe(true);
  });

  it("rejects a non-positive window or request budget", () => {
    expect(() => createRateLimiter({ windowMs: 0, maxRequests: 1 })).toThrow();
    expect(() => createRateLimiter({ windowMs: 1_000, maxRequests: 0 })).toThrow();
  });
});

describe("rate limiter memory", () => {
  it("drops keys whose hits have all expired instead of retaining them", () => {
    const limiter = createRateLimiter({ windowMs: 1_000, maxRequests: 2 });

    // A burst of one-shot callers that are never seen again.
    for (let i = 0; i < 100; i += 1) {
      limiter.check(`caller-${i}`, 0);
    }

    // A later check past the window must sweep them, so an address reused
    // after the window starts from a clean budget rather than a stale log.
    limiter.check("caller-0", 5_000);
    expect(limiter.check("caller-0", 5_000).allowed).toBe(true);
    expect(limiter.check("caller-0", 5_000).allowed).toBe(false);
  });

  it("endpoint-namespaced keys keep separate rate limit quotas for different endpoints (B7)", () => {
    const limiter = createRateLimiter({ windowMs: 60_000, maxRequests: 2 });
    const ip = "192.168.1.1";

    expect(limiter.check(`places-autocomplete:${ip}`, 0).allowed).toBe(true);
    expect(limiter.check(`places-autocomplete:${ip}`, 0).allowed).toBe(true);
    expect(limiter.check(`places-autocomplete:${ip}`, 0).allowed).toBe(false);

    // difficulty endpoint quota is separate
    expect(limiter.check(`difficulty:${ip}`, 0).allowed).toBe(true);
    expect(limiter.check(`difficulty:${ip}`, 0).allowed).toBe(true);
  });

  it("relaxed session check rate limiter allows up to 60 requests per 15-minute window (B8)", () => {
    const limiter = createRateLimiter({ windowMs: 15 * 60_000, maxRequests: 60 });
    const ip = "shared-nat-ip";

    for (let i = 0; i < 60; i++) {
      expect(limiter.check(ip, 0).allowed).toBe(true);
    }
    expect(limiter.check(ip, 0).allowed).toBe(false);
  });
});
