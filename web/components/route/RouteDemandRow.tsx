import type { ReactElement } from "react";
import type { RouteDemand } from "@/lib/types";
import { demandColor } from "@/lib/theme";

const DEMAND_ICON: Record<string, ReactElement> = {
  afterDark: <MoonIcon />,
  fastRoads: <SpeedIcon />,
  merges: <MergeIcon />,
  complexIntersections: <TurnIcon />,
  weatherVisibility: <WeatherIcon />,
  sustainedDrive: <ClockIcon />,
  traffic: <CarIcon />,
  roadConditions: <RoadIcon />,
};

const LEVEL_LABEL: Record<RouteDemand["level"], string> = {
  low: "Low",
  moderate: "Elevated",
  high: "High",
};

// Ported from ios/Roam/Features/Results/ResultsSupportingViews.swift (RouteDemandRow).
export function RouteDemandRow({ demand }: { demand: RouteDemand }) {
  const color = demandColor(demand.level);
  const icon = DEMAND_ICON[demand.id] ?? <DotsIcon />;

  return (
    <div className="flex flex-col gap-2 py-2.5">
      <div className="flex items-start gap-3">
        <div
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-roam-tiny"
          style={{ backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`, color }}
        >
          {icon}
        </div>
        <div className="flex flex-1 flex-col gap-0.5">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-[15px] font-semibold text-ink-primary">
              {demand.title}
            </span>
            <span
              className="rounded-full px-1.5 py-0.5 text-[11px] font-bold"
              style={{
                backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`,
                color,
              }}
            >
              {LEVEL_LABEL[demand.level]}
            </span>
          </div>
          <p className="text-[13px] leading-snug text-ink-secondary">
            {demand.evidence}
          </p>
        </div>
      </div>
      <div className="h-[5px] w-full overflow-hidden rounded-full bg-white/10">
        <div
          className="h-full rounded-full transition-all duration-700 ease-out"
          style={{
            width: `${Math.round(Math.max(0, Math.min(1, demand.intensity)) * 100)}%`,
            backgroundColor: color,
          }}
        />
      </div>
    </div>
  );
}

function MoonIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path
        d="M20 14.5A8.5 8.5 0 1 1 9.5 4a6.7 6.7 0 0 0 10.5 10.5Z"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinejoin="round"
      />
    </svg>
  );
}
function SpeedIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path d="M4 15a8 8 0 1 1 16 0" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      <path d="M12 15 16 9" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}
function MergeIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path d="M6 4v6c0 4 4 4 6 6l4 4M18 4l-4 4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function TurnIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path d="M6 5v7a4 4 0 0 0 4 4h8m0 0-3-3m3 3-3 3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function WeatherIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path d="M7 16.5a4 4 0 1 1 1-7.9 5 5 0 0 1 9.5 2A3.5 3.5 0 0 1 17 17H7Z" stroke="currentColor" strokeWidth="1.6" />
      <path d="M9 20l1-2M13 20l1-2" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}
function ClockIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <circle cx="12" cy="12" r="8.2" stroke="currentColor" strokeWidth="1.7" />
      <path d="M12 7.5V12l3 2" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function CarIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path d="M4 16v-2.5L6 9h12l2 4.5V16m-14 0h14m-14 0a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3Zm14 0a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  );
}
function RoadIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <path d="M8 4 5 20M16 4l3 16M12 8v2m0 4v2" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}
function DotsIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-4 w-4">
      <circle cx="6" cy="12" r="1.6" fill="currentColor" />
      <circle cx="12" cy="12" r="1.6" fill="currentColor" />
      <circle cx="18" cy="12" r="1.6" fill="currentColor" />
    </svg>
  );
}
