import type { ReactNode } from "react";

export function Card({
  children,
  className = "",
  elevated = false,
}: {
  children: ReactNode;
  className?: string;
  elevated?: boolean;
}) {
  return (
    <div
      className={`rounded-roam border ${
        elevated
          ? "border-card-strong bg-card-elevated shadow-roam-md"
          : "border-card bg-card shadow-roam"
      } p-[18px] ${className}`}
    >
      {children}
    </div>
  );
}

export function SectionHeader({
  title,
  subtitle,
}: {
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="mb-3 flex flex-col gap-1">
      <h2 className="text-[20px] font-semibold tracking-[-0.2px] text-ink-primary">
        {title}
      </h2>
      {subtitle ? (
        <p className="text-sm text-ink-secondary">{subtitle}</p>
      ) : null}
    </div>
  );
}

export function MicroLabel({ children }: { children: ReactNode }) {
  return (
    <span className="text-[11px] font-bold uppercase tracking-[1.1px] text-ink-label">
      {children}
    </span>
  );
}

export function Pill({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: "neutral" | "accent" | "positive" | "safety" | "danger";
}) {
  const toneClasses: Record<string, string> = {
    neutral: "bg-black/5 text-ink-secondary",
    accent: "bg-accent/15 text-accent",
    positive: "bg-positive/15 text-positive",
    safety: "bg-safety/15 text-safety",
    danger: "bg-danger/15 text-danger",
  };
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${toneClasses[tone]}`}
    >
      {children}
    </span>
  );
}
