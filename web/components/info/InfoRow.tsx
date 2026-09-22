import type { ReactNode } from "react";

export function InfoRow({
  icon,
  title,
  detail,
  tone = "accent",
  badge,
}: {
  icon: ReactNode;
  title: string;
  detail: string;
  tone?: "accent" | "safety" | "positive" | "secondary";
  badge?: string;
}) {
  const toneColor: Record<string, string> = {
    accent: "var(--accent)",
    safety: "var(--safety)",
    positive: "var(--positive)",
    secondary: "var(--ink-secondary)",
  };
  const color = toneColor[tone];

  return (
    <div className="flex items-start gap-4 py-4">
      <div
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md border border-current/10"
        style={{ backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`, color }}
      >
        {icon}
      </div>
      <div className="flex flex-1 flex-col gap-0.5">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-[14px] font-semibold text-ink-primary">
            {title}
          </span>
          {badge ? (
            <span
              className="rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide"
              style={{ backgroundColor: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
            >
              {badge}
            </span>
          ) : null}
        </div>
        <p className="max-w-3xl text-[13px] leading-5 text-ink-secondary">
          {detail}
        </p>
      </div>
    </div>
  );
}

export function NumberedStep({
  number,
  title,
  detail,
}: {
  number: number;
  title: string;
  detail: string;
}) {
  return (
    <div className="flex items-start gap-3.5 py-3">
      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent text-sm font-bold text-white">
        {number}
      </span>
      <div className="flex flex-1 flex-col gap-0.5">
        <span className="text-[15px] font-semibold text-ink-primary">
          {title}
        </span>
        <p className="text-[13px] leading-relaxed text-ink-secondary">
          {detail}
        </p>
      </div>
    </div>
  );
}

export function Divider() {
  return <div className="border-t border-card" />;
}
