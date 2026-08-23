"use client";

import { useEffect, useState } from "react";
import type { DifficultyLabel } from "@/lib/types";
import { difficultyColor } from "@/lib/theme";
import { formatScore } from "@/lib/format";

// Ported from ios/Roam/Components/ScoreGaugeView.swift.
export function ScoreGauge({
  score,
  label,
}: {
  score: number;
  label: DifficultyLabel;
}) {
  const [progress, setProgress] = useState(0);
  const target = Math.min(Math.max(score / 10, 0), 1);
  const radius = 90;
  const circumference = 2 * Math.PI * radius;

  useEffect(() => {
    const raf = requestAnimationFrame(() => setProgress(target));
    return () => cancelAnimationFrame(raf);
  }, [target]);

  const color = difficultyColor(label);

  return (
    <div className="relative flex h-[204px] w-[204px] items-center justify-center">
      <svg viewBox="0 0 204 204" className="absolute inset-0 -rotate-90">
        <circle
          cx="102"
          cy="102"
          r={radius}
          fill="none"
          stroke="var(--card-stroke-strong)"
          strokeWidth="14"
        />
        <circle
          cx="102"
          cy="102"
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth="14"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - progress)}
          style={{ transition: "stroke-dashoffset 1.1s cubic-bezier(0.22,1,0.36,1)" }}
        />
      </svg>
      <div className="flex flex-col items-center gap-0.5">
        <span className="text-[56px] font-bold leading-none tracking-tight text-ink-primary tabular-nums">
          {formatScore(score)}
        </span>
        <span className="text-[11px] font-bold tracking-[1.2px] text-ink-tertiary">
          OUT OF 10
        </span>
      </div>
    </div>
  );
}
