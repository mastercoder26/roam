import type { ScoreEvidence } from "@/lib/types";
import { Card } from "@/components/ui/Card";

const SIGNAL_TITLE: Record<string, string> = {
  routeGeometry: "Route geometry",
  trafficTiming: "Traffic-aware timing",
  speedLimits: "Posted speed limits",
  weather: "Live weather",
  roadMetadata: "Road metadata",
  turnControls: "Turn controls",
};

const LEVEL_META: Record<
  ScoreEvidence["level"],
  { title: string; color: string }
> = {
  wellSupported: { title: "Well supported", color: "var(--positive)" },
  partial: { title: "Partial evidence", color: "var(--accent)" },
  limited: { title: "Limited evidence", color: "var(--safety)" },
};

// Ported from ios/Roam/Components/RouteEvidenceCard.swift. Intentionally
// avoids presenting coverage as a confidence percentage or safety claim.
export function EvidenceCard({ evidence }: { evidence?: ScoreEvidence }) {
  const meta = LEVEL_META[evidence?.level ?? "limited"];
  const percent = evidence ? Math.round(evidence.inputCoverage * 100) : null;

  return (
    <Card className="w-full max-w-md">
      <div className="flex items-start gap-2.5">
        <div
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: `color-mix(in srgb, ${meta.color} 15%, transparent)` }}
        >
          <svg viewBox="0 0 24 24" fill="none" className="h-3.5 w-3.5" style={{ color: meta.color }}>
            <path d="M12 3 20 7v5c0 5-3.4 8.4-8 9-4.6-.6-8-4-8-9V7l8-4Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
            <path d="m9 12 2 2 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <div className="flex flex-1 flex-col">
          <span className="text-[15px] font-semibold text-ink-primary">
            Evidence coverage
          </span>
          <span className="text-[13px]" style={{ color: meta.color }}>
            {meta.title}
          </span>
        </div>
        {percent !== null ? (
          <span className="pt-0.5 text-[13px] font-bold tabular-nums text-ink-primary">
            {percent}%
          </span>
        ) : null}
      </div>

      {evidence ? (
        <>
          <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
            <div
              className="h-full rounded-full transition-all duration-700"
              style={{
                width: `${percent}%`,
                backgroundColor: meta.color,
              }}
            />
          </div>
          <p className="mt-2 text-[12.5px] text-ink-secondary">
            {evidence.verifiedSignals.length} of{" "}
            {evidence.verifiedSignals.length + evidence.missingSignals.length}{" "}
            route inputs verified.
          </p>
          {evidence.missingSignals.length > 0 ? (
            <p className="mt-1 text-[12.5px] text-ink-secondary">
              Unavailable now:{" "}
              {evidence.missingSignals
                .map((signal) => SIGNAL_TITLE[signal] ?? signal)
                .join(", ")}
              .
            </p>
          ) : null}
        </>
      ) : (
        <p className="mt-2 text-[12.5px] text-ink-secondary">
          This route came from an analysis that did not report which inputs
          were verified.
        </p>
      )}

      <p className="mt-3 text-[11px] leading-snug text-ink-tertiary">
        Coverage describes available route inputs, not a prediction of safety
        or whether someone should drive.
      </p>
    </Card>
  );
}
