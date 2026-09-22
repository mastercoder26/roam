"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
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
  const searchParams = useSearchParams();
  const [origin, setOrigin] = useState(() => searchParams?.get("origin") ?? "");
  const [destination, setDestination] = useState(() => searchParams?.get("destination") ?? "");
  const [departure, setDeparture] = useState<Date>(() => defaultDepartureDate());
  const [isMounted, setIsMounted] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<DifficultyResponse | null>(null);
  const [submittedOrigin, setSubmittedOrigin] = useState("");
  const [submittedDestination, setSubmittedDestination] = useState("");
  const [recentAddresses, setRecentAddresses] = useState<string[]>([]);
  const [isLocating, setIsLocating] = useState(false);
  const analyzeControllerRef = useRef<AbortController | null>(null);

  useEffect(() => {
    setIsMounted(true);
    setDeparture(defaultDepartureDate());
  }, []);

  useEffect(() => {
    const urlOrigin = searchParams?.get("origin");
    const urlDestination = searchParams?.get("destination");
    if (urlOrigin !== null && urlOrigin !== undefined && urlOrigin !== origin) {
      setOrigin(urlOrigin);
    }
    if (urlDestination !== null && urlDestination !== undefined && urlDestination !== destination) {
      setDestination(urlDestination);
    }
  }, [searchParams]);

  useEffect(() => {
    return () => {
      analyzeControllerRef.current?.abort();
    };
  }, []);

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

  function syncUrlParams(newOrigin: string, newDest: string) {
    if (typeof window === "undefined") return;
    try {
      const url = new URL(window.location.href);
      if (newOrigin.trim()) {
        url.searchParams.set("origin", newOrigin.trim());
      } else {
        url.searchParams.delete("origin");
      }
      if (newDest.trim()) {
        url.searchParams.set("destination", newDest.trim());
      } else {
        url.searchParams.delete("destination");
      }
      window.history.replaceState(null, "", url.toString());
    } catch {
      // Route URL state sync is best-effort
    }
  }

  function swap() {
    setOrigin(destination);
    setDestination(origin);
    syncUrlParams(destination, origin);
  }

  function applyExample(example: { origin: string; destination: string }) {
    setOrigin(example.origin);
    setDestination(example.destination);
    syncUrlParams(example.origin, example.destination);
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

    analyzeControllerRef.current?.abort();
    const controller = new AbortController();
    analyzeControllerRef.current = controller;

    syncUrlParams(origin, destination);
    setIsLoading(true);
    setError(null);
    try {
      const token = await getToken();
      if (!token) {
        throw new RoamApiError("Sign in to analyze routes.", 401, "UNAUTHORIZED");
      }
      const response = await analyzeRoute(
        { origin, destination, departureTime: departure, includeAlternates: true },
        token,
        { signal: controller.signal, timeoutMs: 20_000 }
      );
      setResult(response);
      setSubmittedOrigin(origin.trim());
      setSubmittedDestination(destination.trim());
      rememberAddresses([origin, destination]);
    } catch (err) {
      if (controller.signal.aborted) {
        return;
      }
      setResult(null);
      setError(
        err instanceof Error ? err.message : "Route analysis failed unexpectedly."
      );
    } finally {
      if (!controller.signal.aborted) {
        setIsLoading(false);
      }
    }
  }

  return (
    <div className="flex flex-col gap-10">
      <form onSubmit={handleSubmit} className="mx-auto max-w-4xl overflow-visible rounded-roam-lg border border-card bg-card shadow-roam-md">
          <div className="relative z-20 flex flex-col p-5 sm:p-7">
            <div className="mb-6">
              <span className="text-[10px] font-semibold uppercase tracking-[0.14em] text-accent">Trip details</span>
              <p className="mt-2 text-sm leading-5 text-ink-secondary">Start with the places you know. You can fine-tune the route after scoring.</p>
            </div>

            <Card className="relative flex flex-col divide-y divide-card !rounded-xl !p-0">
              <FieldRow
                label="From"
                value={origin}
                onChange={setOrigin}
                placeholder="Address, city, or landmark"
                iconColor="var(--accent)"
                listId="origin-addresses"
                suggestions={originSuggestions}
                autoComplete="section-origin street-address"
                action={
                  <button
                    type="button"
                    onClick={useCurrentLocation}
                    disabled={isLocating}
                    className="roam-jiggle inline-flex shrink-0 items-center gap-1.5 text-[10px] font-semibold text-accent transition-colors hover:text-ink-primary disabled:opacity-60"
                  >
                    <LocationArrowIcon className="h-3.5 w-3.5" />
                    {isLocating ? "Locating…" : "Use my location"}
                  </button>
                }
              />
              <FieldRow
                label="To"
                value={destination}
                onChange={setDestination}
                placeholder="Address, city, or landmark"
                iconColor="var(--ink-secondary)"
                listId="destination-addresses"
                suggestions={destinationSuggestions}
                autoComplete="section-destination street-address"
              />
              <button
                type="button"
                onClick={swap}
                disabled={!origin.trim() && !destination.trim()}
                aria-label="Swap starting location and destination"
                className={`absolute right-3 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-lg border border-card-strong bg-card text-ink-primary shadow-roam transition-[opacity,transform] duration-150 [transition-timing-function:var(--motion-ease-out)] active:scale-[0.97] ${
                  origin.trim() || destination.trim()
                    ? "pointer-events-auto scale-100 opacity-100"
                    : "pointer-events-none scale-95 opacity-0"
                }`}
              >
                <SwapIcon className="h-4 w-4" />
              </button>
            </Card>

            <label className="mt-3 flex items-center gap-3 rounded-xl border border-card bg-card-elevated/60 px-4 py-3.5">
              <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-card text-accent">
                <CalendarIcon className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="mb-1 block text-[10px] font-semibold uppercase tracking-[0.12em] text-ink-label">Leave around</span>
                <input
                  type="datetime-local"
                  value={isMounted ? toDateTimeLocalValue(departure) : ""}
                  suppressHydrationWarning
                  onChange={(event) => {
                    const parsed = fromDateTimeLocalValue(event.target.value);
                    if (parsed) setDeparture(parsed);
                  }}
                  className="w-full bg-transparent text-[13px] font-medium text-ink-primary outline-none"
                />
              </span>
            </label>

            {!origin && !destination ? (
              <div className="mt-5">
                <span className="text-[10px] font-semibold uppercase tracking-[0.12em] text-ink-label">Popular examples</span>
                <div className="mt-2 flex flex-wrap gap-2">
                  {EXAMPLE_ROUTES.map((example) => (
                    <button
                      key={example.origin}
                      type="button"
                      onClick={() => applyExample(example)}
                      className="roam-jiggle rounded-full border border-card-strong px-3 py-1.5 text-[11px] font-medium text-ink-secondary transition-[color,border-color,background-color] hover:border-ink-primary hover:bg-card-elevated hover:text-ink-primary"
                    >
                      {example.label}
                    </button>
                  ))}
                </div>
              </div>
            ) : null}

            <div className="mt-auto pt-6">
              {!isLoaded ? (
                <div className="flex min-h-12 items-center justify-center rounded-lg bg-disabled/60 px-5 text-[13px] font-semibold text-ink-tertiary">
                  <span className="roam-spin mr-2 h-4 w-4 rounded-full border-2 border-ink-tertiary/30 border-t-ink-tertiary" />
                  Loading session…
                </div>
              ) : (
                <>
                  <SignedIn>
                    <button
                      type="submit"
                      disabled={!canAnalyze}
                      className={`roam-jiggle flex min-h-12 w-full items-center justify-center gap-2 rounded-lg px-5 text-[13px] font-semibold transition-[color,background-color,box-shadow,transform] duration-150 ${
                        canAnalyze
                          ? "bg-ink-primary text-white shadow-roam-md hover:bg-accent"
                          : "cursor-not-allowed bg-disabled text-ink-tertiary"
                      }`}
                    >
                      {isLoading ? (
                        <><span className="roam-spin h-4 w-4 rounded-full border-2 border-white/30 border-t-white" />Analyzing route</>
                      ) : (
                        <><SparkleIcon className="h-4 w-4" />Analyze route</>
                      )}
                    </button>
                  </SignedIn>
                  <SignedOut>
                    <SignInButton mode="modal">
                      <button type="button" className="roam-jiggle flex min-h-12 w-full items-center justify-center gap-2 rounded-lg bg-ink-primary px-5 text-[13px] font-semibold text-white shadow-roam-md transition-colors hover:bg-accent">
                        Sign in to analyze
                      </button>
                    </SignInButton>
                  </SignedOut>
                </>
              )}

              {error ? (
                <div className="mt-3 flex items-start gap-2.5 rounded-lg border border-safety/25 bg-safety/[0.07] px-3.5 py-3 text-[13px] leading-5 text-ink-primary">
                  <WarningIcon className="h-4 w-4 shrink-0 translate-y-0.5 text-safety" />
                  <span>{error}</span>
                </div>
              ) : null}

              {!isLoaded ? null : !isSignedIn ? (
                <p className="mt-3 text-center text-[11px] leading-4 text-ink-tertiary">Sign in to score live routes and compare alternatives.</p>
              ) : null}
            </div>
          </div>
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
  const blurTimerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (blurTimerRef.current !== null) {
        window.clearTimeout(blurTimerRef.current);
      }
    };
  }, []);

  const normalizedValue = value.trim().toLowerCase();
  const visibleSuggestions = useMemo(() => {
    if (normalizedValue.length === 0) {
      return suggestions.slice(0, 5);
    }
    return suggestions
      .filter((suggestion) => {
        const normalizedSuggestion = suggestion.toLowerCase();
        if (normalizedSuggestion === normalizedValue) return false;
        return normalizedSuggestion.includes(normalizedValue);
      })
      .slice(0, 5);
  }, [normalizedValue, suggestions]);
  const listboxId = `${listId}-listbox`;

  function chooseSuggestion(suggestion: string) {
    if (blurTimerRef.current !== null) {
      window.clearTimeout(blurTimerRef.current);
      blurTimerRef.current = null;
    }
    onChange(suggestion);
    setIsOpen(false);
    setActiveIndex(-1);
  }

  function handleFocus() {
    if (blurTimerRef.current !== null) {
      window.clearTimeout(blurTimerRef.current);
      blurTimerRef.current = null;
    }
    setIsOpen(true);
  }

  function handleBlur() {
    if (blurTimerRef.current !== null) {
      window.clearTimeout(blurTimerRef.current);
    }
    blurTimerRef.current = window.setTimeout(() => {
      setIsOpen(false);
      blurTimerRef.current = null;
    }, 250);
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
            onFocus={handleFocus}
            onBlur={handleBlur}
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
              className="roam-popover absolute left-0 right-0 top-full z-40 mt-3 border border-ink-primary/20 bg-card py-1 shadow-roam-lg"
            >
              {normalizedValue.length === 0 ? (
                <div className="border-b border-ink-primary/10 px-3 py-1.5 text-[9px] font-bold uppercase tracking-[0.14em] text-ink-label">
                  Recent & Suggested
                </div>
              ) : null}
              {visibleSuggestions.map((suggestion, index) => (
                <button
                  id={`${listboxId}-${index}`}
                  key={suggestion}
                  type="button"
                  role="option"
                  aria-selected={index === activeIndex}
                  onPointerDown={(event) => {
                    event.preventDefault();
                    if (blurTimerRef.current !== null) {
                      window.clearTimeout(blurTimerRef.current);
                      blurTimerRef.current = null;
                    }
                  }}
                  onTouchEnd={(event) => {
                    event.preventDefault();
                    chooseSuggestion(suggestion);
                  }}
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
