// Ported from the `ScoredRoute` formatting extension in
// ios/Roam/Models/RouteDifficultyModels.swift.

const METERS_PER_MILE = 1609.344;

export function formatDistanceMeters(distanceMeters: number): string {
  return `${(distanceMeters / METERS_PER_MILE).toFixed(1)} mi`;
}

export function formatDurationSeconds(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes} min`;
}

export function formatDelaySeconds(trafficDelaySeconds: number): string | null {
  if (trafficDelaySeconds <= 0) return null;
  return `+${formatDurationSeconds(trafficDelaySeconds)}`;
}

export function formatScore(score: number): string {
  return score.toFixed(1);
}

export function formatPercent(value: number): string {
  return `${Math.round(Math.max(0, Math.min(1, value)) * 100)}%`;
}

/**
 * Builds an ISO-8601 timestamp with the browser's local UTC offset, matching
 * the format the backend's `departureTime` validator accepts
 * (`YYYY-MM-DDTHH:mm:ss.sss±HH:MM`). `Date#toISOString` always renders UTC,
 * which would silently shift a "6 PM departure" to whatever hour 6 PM local
 * time is in UTC once the server reads it back as a plain instant — the
 * separate `departureLocalMinutes` field carries the actual wall-clock time.
 */
export function toIsoWithLocalOffset(date: Date): string {
  const pad = (value: number, width = 2) => String(value).padStart(width, "0");
  const offsetMinutesTotal = -date.getTimezoneOffset();
  const sign = offsetMinutesTotal >= 0 ? "+" : "-";
  const absOffset = Math.abs(offsetMinutesTotal);
  const offsetHours = pad(Math.floor(absOffset / 60));
  const offsetMinutes = pad(absOffset % 60);

  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
    `.${pad(date.getMilliseconds(), 3)}${sign}${offsetHours}:${offsetMinutes}`
  );
}

export function departureLocalMinutes(date: Date): number {
  return date.getHours() * 60 + date.getMinutes();
}

/** Default departure: two hours from now, on the minute. */
export function defaultDepartureDate(): Date {
  const date = new Date(Date.now() + 2 * 60 * 60 * 1000);
  date.setSeconds(0, 0);
  return date;
}

/** For an `<input type="datetime-local">` value bound to a local `Date`. */
export function toDateTimeLocalValue(date: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours()
  )}:${pad(date.getMinutes())}`;
}

export function fromDateTimeLocalValue(value: string): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}
