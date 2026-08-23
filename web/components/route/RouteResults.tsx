"use client";

import { useState } from "react";
import type { AlternateRoute, DifficultyResponse, ScoredRoute } from "@/lib/types";
import { Card, SectionHeader, Pill } from "@/components/ui/Card";
import { ScoreGauge } from "@/components/route/ScoreGauge";
import { EvidenceCard } from "@/components/route/EvidenceCard";
import { RouteDemandRow } from "@/components/route/RouteDemandRow";
import { RoutePolylinePreview } from "@/components/route/RoutePolylinePreview";
import { difficultyColor } from "@/lib/theme";
import {
  formatDelaySeconds,
  formatDistanceMeters,
  formatDurationSeconds,
  formatScore,
} from "@/lib/format";

export function RouteResults({
  result,
  origin,
  destination,
}: {
  result: DifficultyResponse;
  origin: string;
  destination: string;
}) {
  const allRoutes: (ScoredRoute | AlternateRoute)[] = [
    result.primaryRoute,
    ...result.alternateRoutes,
  ];
  const [selectedIndex, setSelectedIndex] = useState(0);
  const selected = allRoutes[selectedIndex] ?? result.primaryRoute;
  const color = difficultyColor(selected.label);

  return (
    <div className="roam-reveal flex flex-col gap-6">
      <Card className="flex items-center justify-between gap-3 !py-3">
        <div className="flex min-w-0 flex-col gap-1">
          <span className="truncate text-[14px] font-semibold text-ink-primary">
            {origin}
          </span>
          <span className="truncate text-[14px] font-semibold text-ink-primary">
            {destination}
          </span>
        </div>
        {result.alternateRoutes.length > 0 ? (
          <Pill tone="accent">
            {allRoutes.length} route{allRoutes.length > 1 ? "s" : ""}
          </Pill>
        ) : null}
      </Card>

      <Card className="flex flex-col items-center gap-3 py-8">
        <ScoreGauge score={selected.score} label={selected.label} />
        <span
          className="rounded-full px-3.5 py-1.5 text-[14px] font-semibold"
          style={{
            backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`,
            color,
          }}
        >
          {selected.label}
        </span>
        <EvidenceCard evidence={selected.uncertainty?.evidence} />
      </Card>

      {result.alternateRoutes.length > 0 ? (
        <div>
          <SectionHeader
            title="Route choices"
            subtitle="Ranked easiest-first, exactly as the backend returns them."
          />
          <div className="flex flex-col gap-2.5">
            {allRoutes.map((route, index) => (
              <button
                key={index}
                onClick={() => setSelectedIndex(index)}
                className={`flex items-center gap-3.5 rounded-roam border px-[18px] py-[14px] text-left transition-colors ${
                  index === selectedIndex
                    ? "border-accent/50 bg-accent/10"
                    : "border-card bg-card hover:border-card-strong"
                }`}
              >
                <div className="flex flex-1 flex-col gap-1">
                  <div className="flex items-center gap-2">
                    <span
                      className="text-lg font-bold tabular-nums"
                      style={{ color: difficultyColor(route.label) }}
                    >
                      {formatScore(route.score)}
                    </span>
                    <span className="text-sm font-semibold text-ink-secondary">
                      {route.label}
                    </span>
                  </div>
                  {route.reasons[0] ? (
                    <span className="text-[13px] text-ink-primary">
                      {route.reasons[0]}
                    </span>
                  ) : null}
                  <div className="flex gap-3 text-xs text-ink-secondary">
                    <span>{formatDurationSeconds(route.durationSeconds)}</span>
                    <span>{formatDistanceMeters(route.distanceMeters)}</span>
                  </div>
                </div>
                {"scoreDelta" in route && route.scoreDelta !== undefined ? (
                  <span
                    className={`rounded-full px-2 py-1 text-xs font-semibold ${
                      route.scoreDelta >= 0
                        ? "bg-safety/15 text-safety"
                        : "bg-positive/15 text-positive"
                    }`}
                  >
                    {route.scoreDelta >= 0 ? "+" : ""}
                    {route.scoreDelta.toFixed(1)}
                  </span>
                ) : (
                  index === selectedIndex && (
                    <CheckIcon className="h-5 w-5 text-accent" />
                  )
                )}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <div>
        <SectionHeader title="Trip at a glance" />
        <Card>
          <div className={`grid gap-4 ${formatDelaySeconds(selected.trafficDelaySeconds) ? "grid-cols-3" : "grid-cols-2"}`}>
            <Metric
              label="ETA"
              value={formatDurationSeconds(selected.durationSeconds)}
            />
            {formatDelaySeconds(selected.trafficDelaySeconds) ? (
              <Metric
                label="Delay"
                value={formatDelaySeconds(selected.trafficDelaySeconds)!}
                tone="safety"
              />
            ) : null}
            <Metric
              label="Distance"
              value={formatDistanceMeters(selected.distanceMeters)}
            />
          </div>
          <div className="mt-3 border-t border-card pt-3 text-[13px] text-ink-secondary">
            Normal drive: {formatDurationSeconds(selected.staticDurationSeconds)}
          </div>
        </Card>
      </div>

      <div>
        <SectionHeader title="Route map" subtitle="Explore the surrounding roads with the scored route highlighted." />
        <Card className="!p-0 overflow-hidden">
          <div className="h-[220px] w-full bg-card-elevated">
            <RoutePolylinePreview
              polyline={selected.polyline}
              bounds={selected.bounds}
              color={color}
            />
          </div>
        </Card>
      </div>

      {selected.routeDemands?.length ? (
        <div>
          <SectionHeader
            title="What this route asks of you"
            subtitle="The road conditions that stand out for this drive."
          />
          <Card className="!py-1">
            {selected.routeDemands.map((demand, i) => (
              <div key={demand.id}>
                <RouteDemandRow demand={demand} />
                {i < selected.routeDemands.length - 1 ? (
                  <div className="ml-12 border-t border-card" />
                ) : null}
              </div>
            ))}
          </Card>
        </div>
      ) : null}

      {selected.reasons.length > 0 ? (
        <div>
          <SectionHeader title="Why this score" />
          <div className="flex flex-wrap gap-2">
            {selected.reasons.map((reason) => (
              <span
                key={reason}
                className="rounded-roam-sm bg-card-elevated px-3 py-2 text-sm font-medium text-ink-primary"
              >
                {reason}
              </span>
            ))}
          </div>
        </div>
      ) : null}

      {selected.hotspots?.length ? (
        <div>
          <SectionHeader title="Difficulty hotspots" />
          <Card className="flex flex-col gap-3">
            {selected.hotspots.slice(0, 5).map((hotspot, index) => (
              <div key={index} className="flex items-center gap-3">
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-safety text-xs font-bold text-black">
                  #{hotspot.segmentIndex + 1}
                </span>
                <div className="flex flex-col">
                  <span className="text-sm font-medium text-ink-primary">
                    {hotspot.label ?? `Segment ${hotspot.segmentIndex + 1}`}
                  </span>
                  <span className="text-xs text-ink-secondary">
                    Intensity {Math.round(hotspot.difficulty * 100)}%
                  </span>
                </div>
              </div>
            ))}
          </Card>
        </div>
      ) : null}

      {selected.modelVersion ? (
        <p className="text-center text-xs text-ink-tertiary">
          Scored live by the deployed backend · model {selected.modelVersion}
        </p>
      ) : null}
    </div>
  );
}

function Metric({
  label,
  value,
  tone = "primary",
}: {
  label: string;
  value: string;
  tone?: "primary" | "safety";
}) {
  return (
    <div className="flex flex-col gap-1">
      <span
        className={`text-[19px] font-semibold tabular-nums ${
          tone === "safety" ? "text-safety" : "text-ink-primary"
        }`}
      >
        {value}
      </span>
      <span className="text-[11px] font-medium uppercase tracking-wide text-ink-secondary">
        {label}
      </span>
    </div>
  );
}

function CheckIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <circle cx="12" cy="12" r="10" fill="currentColor" opacity={0.15} />
      <path d="m8 12.5 2.5 2.5L16 9" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
