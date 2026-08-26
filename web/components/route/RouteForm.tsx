"use client";

import { useEffect, useMemo, useState } from "react";
import { useAuth, SignedIn, SignedOut, SignInButton } from "@clerk/nextjs";
import { Card, MicroLabel } from "@/components/ui/Card";
import { RouteResults } from "@/components/route/RouteResults";
import { analyzeRoute, RoamApiError, suggestAddresses } from "@/lib/roamApi";
import {
  defaultDepartureDate,
  fromDateTimeLocalValue,
  toDateTimeLocalValue,
} from "@/lib/format";
import type { DifficultyResponse } from "@/lib/types";

const EXAMPLE_ROUTES = [
  { origin: "Austin, TX", destination: "Dallas, TX", label: "Austin → Dallas" },
  { origin: "San Francisco, CA", destination: "San Jose, CA", label: "SF → San Jose" },
  { origin: "Boston, MA", destination: "New York, NY", label: "Boston → New York" },
];

const RECENT_ADDRESSES_KEY = "roam.recent-addresses";

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
  const [recentAddresses, setRecentAddresses] = useState<string[]>([]);
  const [isLocating, setIsLocating] = useState(false);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(RECENT_ADDRESSES_KEY);
      const parsed: unknown = stored ? JSON.parse(stored) : [];
      if (Array.isArray(parsed)) {
        setRecentAddresses(parsed.filter((value): value is string => typeof value === "string").slice(0, 6));
      }
    } catch {
      // Route planning still works when storage is unavailable or malformed.
    }
  }, []);

  const addressSuggestions = useMemo(
    () => Array.from(new Set([...recentAddresses, ...EXAMPLE_ROUTES.flatMap((route) => [route.origin, route.destination])])),
    [recentAddresses]
  );
  const originMatches = useAddressSuggestions(origin, Boolean(isSignedIn), getToken);
  const destinationMatches = useAddressSuggestions(destination, Boolean(isSignedIn), getToken);
  const originSuggestions = useMemo(
    () => Array.from(new Set([...originMatches, ...addressSuggestions])),
    [originMatches, addressSuggestions]
  );
  const destinationSuggestions = useMemo(
    () => Array.from(new Set([...destinationMatches, ...addressSuggestions])),
    [destinationMatches, addressSuggestions]
  );

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

  function rememberAddresses(values: string[]) {
    const next = Array.from(new Set([...values.map((value) => value.trim()), ...recentAddresses]))
      .filter(Boolean)
      .slice(0, 6);
    setRecentAddresses(next);
    try {
      window.localStorage.setItem(RECENT_ADDRESSES_KEY, JSON.stringify(next));
    } catch {
      // Recent suggestions are a convenience, not a requirement.
    }
  }

  function useCurrentLocation() {
    if (!navigator.geolocation) {
      setError("This browser does not support current-location autofill. Enter your starting address instead.");
      return;
    }

    setIsLocating(true);
    setError(null);
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        setOrigin(`${coords.latitude.toFixed(6)}, ${coords.longitude.toFixed(6)}`);
        setIsLocating(false);
      },
      () => {
        setError("Roam could not access your location. Check browser permission or enter your starting address.");
        setIsLocating(false);
      },
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 }
    );
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
      rememberAddresses([origin, destination]);
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
      <form onSubmit={handleSubmit} className="border-y-2 border-ink-primary bg-transparent py-5 sm:py-7">
        <div className="grid gap-4 lg:grid-cols-[1fr_280px]">
          <Card className="relative flex flex-col divide-y divide-card !rounded-none !border-ink-primary/20 !p-0 !shadow-none">
          <FieldRow
            label="FROM"
            value={origin}
            onChange={setOrigin}
            placeholder="Street address, city, or landmark"
            iconColor="var(--accent)"
            listId="origin-addresses"
            suggestions={originSuggestions}
            autoComplete="section-origin street-address"
            action={
              <button
                type="button"
                onClick={useCurrentLocation}
                disabled={isLocating}
                className="roam-jiggle inline-flex shrink-0 items-center gap-1.5 border-b border-accent/40 px-0.5 py-1 text-[10px] font-bold uppercase tracking-[0.08em] text-accent transition-colors hover:border-accent disabled:opacity-60"
              >
                <LocationArrowIcon className="h-3.5 w-3.5" />
                {isLocating ? "Locating…" : "Use my location"}
              </button>
            }
          />
          <FieldRow
            label="TO"
            value={destination}
            onChange={setDestination}
            placeholder="Street address, city, or landmark"
            iconColor="var(--ink-secondary)"
            listId="destination-addresses"
            suggestions={destinationSuggestions}
            autoComplete="section-destination street-address"
          />
          {origin.trim() && destination.trim() ? (
            <button
              type="button"
              onClick={swap}
              aria-label="Swap starting location and destination"
              className="absolute right-3 top-1/2 flex h-10 w-10 -translate-y-1/2 items-center justify-center border border-ink-primary/20 bg-card text-ink-primary transition-transform hover:rotate-180 active:scale-90"
            >
              <SwapIcon className="h-4 w-4" />
            </button>
          ) : null}
          </Card>

          <div className="flex flex-col gap-3">
            <label className="flex flex-1 items-center gap-3 border border-ink-primary/20 bg-card-elevated px-4 py-3.5">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-card text-accent shadow-roam">
                <CalendarIcon className="h-[18px] w-[18px]" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="mb-1 block text-[10px] font-bold uppercase tracking-[0.12em] text-ink-label">Leave around</span>
                <input
                  type="datetime-local"
                  value={toDateTimeLocalValue(departure)}
                  onChange={(event) => {
                    const parsed = fromDateTimeLocalValue(event.target.value);
                    if (parsed) setDeparture(parsed);
                  }}
                  className="w-full bg-transparent text-[13px] font-bold text-ink-primary outline-none"
                />
              </span>
            </label>

            <SignedIn>
              <button
                type="submit"
                disabled={!canAnalyze}
                className={`roam-jiggle flex min-h-14 items-center justify-center gap-2 px-5 text-[13px] font-bold uppercase tracking-[0.08em] transition-[color,background-color,box-shadow,transform] duration-200 active:scale-[0.97] ${
                  canAnalyze
                    ? "bg-accent text-white shadow-roam-lg"
                    : "cursor-not-allowed bg-disabled text-ink-tertiary"
                }`}
              >
                {isLoading ? (
                  <><span className="roam-spin h-4 w-4 rounded-full border-2 border-white/30 border-t-white" />Analyzing route</>
                ) : (
                  <><SparkleIcon className="h-4 w-4" />Analyze difficulty</>
                )}
              </button>
            </SignedIn>
            <SignedOut>
              <SignInButton mode="modal">
                <button type="button" className="roam-jiggle flex min-h-14 items-center justify-center gap-2 bg-accent px-5 text-[13px] font-bold uppercase tracking-[0.08em] text-white shadow-roam-lg transition-transform active:scale-[0.97]">
                  Sign in to analyze
                </button>
              </SignInButton>
            </SignedOut>
          </div>
        </div>

        {!origin && !destination ? (
          <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-card pt-4">
            <span className="mr-1 text-[11px] font-bold uppercase tracking-[0.1em] text-ink-label">Try a route</span>
            {EXAMPLE_ROUTES.map((example) => (
              <button
                key={example.origin}
                type="button"
                onClick={() => applyExample(example)}
                className="roam-jiggle border border-ink-primary/20 bg-transparent px-3 py-1.5 text-[11px] font-bold uppercase tracking-[0.06em] text-ink-secondary transition-colors hover:border-accent hover:text-accent"
              >
                {example.label}
              </button>
            ))}
          </div>
        ) : null}

        {error ? (
          <div className="mt-4 flex items-start gap-2.5 border border-safety/30 bg-safety/[0.07] px-4 py-3.5 text-sm text-ink-primary">
            <WarningIcon className="h-4 w-4 shrink-0 translate-y-0.5 text-safety" />
            <span>{error}</span>
          </div>
        ) : null}

        {!isLoaded ? (
          <p className="mt-3 text-center text-xs text-ink-tertiary">
            Loading your session…
          </p>
        ) : !isSignedIn ? (
          <p className="mt-3 text-center text-xs leading-5 text-ink-tertiary">
            Sign in to use live route scoring and compare alternate routes.
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

function useAddressSuggestions(
  value: string,
  enabled: boolean,
  getToken: () => Promise<string | null>,
): string[] {
  const [suggestions, setSuggestions] = useState<string[]>([]);

  useEffect(() => {
    const input = value.trim();
    if (!enabled || input.length < 3) {
      setSuggestions([]);
      return;
    }

    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      void getToken()
        .then((token) => token
          ? suggestAddresses(input, token, controller.signal)
          : []
        )
        .then((matches) => {
          if (!controller.signal.aborted) {
            setSuggestions(matches.map((match) => match.label));
          }
        })
        .catch(() => {
          if (!controller.signal.aborted) setSuggestions([]);
        });
    }, 250);

    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [enabled, getToken, value]);

  return suggestions;
}

function FieldRow({
  label,
  value,
  onChange,
  placeholder,
  iconColor,
  listId,
  suggestions,
  autoComplete,
  action,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  iconColor: string;
  listId: string;
  suggestions: string[];
  autoComplete: string;
  action?: React.ReactNode;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);
  const normalizedValue = value.trim().toLowerCase();
  const visibleSuggestions = normalizedValue.length >= 3
    ? suggestions
      .filter((suggestion) => {
        const normalizedSuggestion = suggestion.toLowerCase();
        return normalizedSuggestion.includes(normalizedValue)
          && normalizedSuggestion !== normalizedValue;
      })
      .slice(0, 5)
    : [];
  const listboxId = `${listId}-listbox`;

  function chooseSuggestion(suggestion: string) {
    onChange(suggestion);
    setIsOpen(false);
    setActiveIndex(-1);
  }

  return (
    <div className="flex items-start gap-3.5 px-[18px] py-[17px] pr-14">
      <span
        className="mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full"
        style={{ backgroundColor: iconColor }}
      />
      <div className="min-w-0 flex flex-1 flex-col gap-1">
        <div className="flex items-center justify-between gap-3">
          <MicroLabel>{label}</MicroLabel>
          {action}
        </div>
        <div className="relative">
          <input
            value={value}
            onChange={(event) => {
              onChange(event.target.value);
              setIsOpen(true);
              setActiveIndex(-1);
            }}
            onFocus={() => setIsOpen(true)}
            onBlur={() => window.setTimeout(() => setIsOpen(false), 100)}
            onKeyDown={(event) => {
              if (visibleSuggestions.length === 0) return;
              if (event.key === "ArrowDown") {
                event.preventDefault();
                setIsOpen(true);
                setActiveIndex((index) => (index + 1) % visibleSuggestions.length);
              } else if (event.key === "ArrowUp") {
                event.preventDefault();
                setIsOpen(true);
                setActiveIndex((index) => index <= 0 ? visibleSuggestions.length - 1 : index - 1);
              } else if (event.key === "Enter" && activeIndex >= 0) {
                event.preventDefault();
                chooseSuggestion(visibleSuggestions[activeIndex]);
              } else if (event.key === "Escape") {
                setIsOpen(false);
                setActiveIndex(-1);
              }
            }}
            placeholder={placeholder}
            autoComplete={autoComplete}
            enterKeyHint="next"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={isOpen && visibleSuggestions.length > 0}
            aria-controls={listboxId}
            aria-activedescendant={activeIndex >= 0 ? `${listboxId}-${activeIndex}` : undefined}
            className="w-full bg-transparent text-[16px] font-medium text-ink-primary placeholder:text-ink-tertiary outline-none"
          />
          {isOpen && visibleSuggestions.length > 0 ? (
            <div
              id={listboxId}
              role="listbox"
              className="absolute left-0 right-0 top-full z-40 mt-3 border border-ink-primary/20 bg-card py-1 shadow-roam-lg"
            >
              {visibleSuggestions.map((suggestion, index) => (
                <button
                  id={`${listboxId}-${index}`}
                  key={suggestion}
                  type="button"
                  role="option"
                  aria-selected={index === activeIndex}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => chooseSuggestion(suggestion)}
                  className={`block w-full px-3 py-2.5 text-left text-sm leading-5 transition-colors ${
                    index === activeIndex
                      ? "bg-accent text-white"
                      : "text-ink-primary hover:bg-accent/[0.08]"
                  }`}
                >
                  {suggestion}
                </button>
              ))}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function LocationArrowIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path d="m20 4-7.1 16-2.2-6.7L4 11.1 20 4Z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
    </svg>
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
