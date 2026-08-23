"use client";

import { useState } from "react";
import { useAuth, SignedIn, SignedOut, SignInButton } from "@clerk/nextjs";
import { Card, MicroLabel } from "@/components/ui/Card";
import { RouteResults } from "@/components/route/RouteResults";
import { analyzeRoute, RoamApiError } from "@/lib/roamApi";
import {
  defaultDepartureDate,
  fromDateTimeLocalValue,
  toDateTimeLocalValue,
} from "@/lib/format";
import type { DifficultyResponse } from "@/lib/types";

const EXAMPLE_ROUTES = [
  { origin: "Austin, TX", destination: "Dallas, TX" },
  { origin: "San Francisco, CA", destination: "San Jose, CA" },
  { origin: "Boston, MA", destination: "New York, NY" },
];

export function RouteForm() {
  const { isSignedIn, isLoaded, getToken } = useAuth();
  const [origin, setOrigin] = useState("");
  const [destination, setDestination] = useState("");
  const [departure, setDeparture] = useState<Date>(() => defaultDepartureDate());
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<DifficultyResponse | null>(null);
  const [submittedOrigin, setSubmittedOrigin] = useState("");
  const [submittedDestination, setSubmittedDestination] = useState("");

  const canAnalyze =
    origin.trim().length > 0 && destination.trim().length > 0 && !isLoading;

  function swap() {
    setOrigin(destination);
    setDestination(origin);
  }

  function applyExample(example: { origin: string; destination: string }) {
    setOrigin(example.origin);
    setDestination(example.destination);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!canAnalyze) return;

    setIsLoading(true);
    setError(null);
    try {
      const token = await getToken();
      if (!token) {
        throw new RoamApiError("Sign in to analyze routes.", 401, "UNAUTHORIZED");
      }
      const response = await analyzeRoute(
        { origin, destination, departureTime: departure, includeAlternates: true },
        token
      );
      setResult(response);
      setSubmittedOrigin(origin.trim());
      setSubmittedDestination(destination.trim());
    } catch (err) {
      setResult(null);
      setError(
        err instanceof Error ? err.message : "Route analysis failed unexpectedly."
      );
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <Card className="relative flex flex-col divide-y divide-white/[0.06] !p-0">
          <FieldRow
            label="FROM"
            value={origin}
            onChange={setOrigin}
            placeholder="Enter a starting location"
            iconColor="rgb(5,107,235)"
          />
          <FieldRow
            label="TO"
            value={destination}
            onChange={setDestination}
            placeholder="Enter a destination"
            iconColor="var(--ink-secondary)"
          />
          {origin.trim() && destination.trim() ? (
            <button
              type="button"
              onClick={swap}
              aria-label="Swap starting location and destination"
              className="absolute right-2.5 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-full border border-card-strong bg-card-elevated text-ink-primary transition-transform active:scale-90"
            >
              <SwapIcon className="h-4 w-4" />
            </button>
          ) : null}
        </Card>

        <Card className="flex items-center gap-2.5">
          <CalendarIcon className="h-5 w-5 shrink-0 text-ink-secondary" />
          <input
            type="datetime-local"
            value={toDateTimeLocalValue(departure)}
            onChange={(event) => {
              const parsed = fromDateTimeLocalValue(event.target.value);
              if (parsed) setDeparture(parsed);
            }}
            className="w-full bg-transparent text-[15px] font-medium text-ink-primary outline-none [color-scheme:dark]"
          />
        </Card>

        {!origin && !destination ? (
          <div className="flex flex-wrap gap-2">
            {EXAMPLE_ROUTES.map((example) => (
              <button
                key={example.origin}
                type="button"
                onClick={() => applyExample(example)}
                className="rounded-full border border-card bg-card px-3 py-1.5 text-xs font-medium text-ink-secondary transition-colors hover:border-card-strong hover:text-ink-primary"
              >
                {example.origin} → {example.destination}
              </button>
            ))}
          </div>
        ) : null}

        {error ? (
          <div className="flex items-start gap-2.5 rounded-roam bg-safety/10 px-4 py-3.5 text-sm text-ink-primary">
            <WarningIcon className="h-4 w-4 shrink-0 translate-y-0.5 text-safety" />
            <span>{error}</span>
          </div>
        ) : null}

        <SignedIn>
          <button
            type="submit"
            disabled={!canAnalyze}
            className={`flex items-center justify-center gap-2 rounded-full py-[17px] text-[16px] font-semibold transition-transform active:scale-[0.98] ${
              canAnalyze
                ? "bg-ink-primary text-canvas shadow-roam-lg"
                : "cursor-not-allowed bg-white/10 text-ink-tertiary"
            }`}
          >
            {isLoading ? (
              <>
                <span className="roam-spin h-4 w-4 rounded-full border-2 border-canvas/30 border-t-canvas" />
                Analyzing route
              </>
            ) : (
              <>
                <SparkleIcon className="h-4 w-4" />
                Analyze difficulty
              </>
            )}
          </button>
        </SignedIn>
        <SignedOut>
          <SignInButton mode="modal">
            <button
              type="button"
              className="flex items-center justify-center gap-2 rounded-full bg-ink-primary py-[17px] text-[16px] font-semibold text-canvas shadow-roam-lg transition-transform active:scale-[0.98]"
            >
              Sign in to analyze this route
            </button>
          </SignInButton>
        </SignedOut>
        {!isLoaded ? (
          <p className="text-center text-xs text-ink-tertiary">
            Loading your session…
          </p>
        ) : !isSignedIn ? (
          <p className="text-center text-xs text-ink-tertiary">
            Roam scores routes with the same live backend as the iOS app,
            which requires a signed-in session to call Google&apos;s routing
            APIs responsibly.
          </p>
        ) : null}
      </form>

      {result ? (
        <RouteResults
          result={result}
          origin={submittedOrigin}
          destination={submittedDestination}
        />
      ) : null}
    </div>
  );
}

function FieldRow({
  label,
  value,
  onChange,
  placeholder,
  iconColor,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  iconColor: string;
}) {
  return (
    <div className="flex items-start gap-3.5 px-[18px] py-[15px]">
      <span
        className="mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full"
        style={{ backgroundColor: iconColor }}
      />
      <div className="flex flex-1 flex-col gap-1">
        <MicroLabel>{label}</MicroLabel>
        <input
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
          className="w-full bg-transparent text-[16px] font-medium text-ink-primary placeholder:text-ink-tertiary outline-none"
        />
      </div>
    </div>
  );
}

function SwapIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M7 7h11l-3-3M17 17H6l3 3" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function CalendarIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <rect x="4" y="5.5" width="16" height="14.5" rx="2.4" stroke="currentColor" strokeWidth="1.7" />
      <path d="M4 10h16M8 3.5v3M16 3.5v3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}
function SparkleIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
      <path d="M12 2.5 13.9 9l6.6 1.9-6.6 1.9L12 19.5 10.1 12.8 3.5 10.9l6.6-1.9L12 2.5Z" />
    </svg>
  );
}
function WarningIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M12 3.5 21.5 20h-19L12 3.5Z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
      <path d="M12 9.5v4.2M12 16.7v.3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}
