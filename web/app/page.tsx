import { Suspense } from "react";
import { RouteForm } from "@/components/route/RouteForm";

export default function HomePage() {
  return (
    <div className="flex flex-col gap-10 sm:gap-14">
      <section className="roam-enter grid gap-8 border-b border-card pb-10 lg:grid-cols-[1.15fr_0.85fr] lg:items-end lg:pb-12">
        <div>
          <p className="mb-4 text-[11px] font-semibold uppercase tracking-[0.14em] text-accent">Route intelligence</p>
          <h1 className="max-w-3xl text-[clamp(3rem,7vw,6.4rem)] font-semibold leading-[0.92] tracking-[-0.055em] text-ink-primary">
            Know the drive before you take it.
          </h1>
        </div>
        <div className="max-w-xl lg:justify-self-end lg:pb-1">
          <p className="text-base leading-7 text-ink-secondary sm:text-lg">
            Compare routes by the attention they demand, not only the minutes
            they save. Roam reads traffic, weather, road geometry, and turns in
            one clear view.
          </p>
          <div className="mt-6 flex flex-wrap gap-x-6 gap-y-2 border-t border-card pt-4 text-xs font-medium text-ink-secondary">
            <SignalLabel index="01" label="Live conditions" />
            <SignalLabel index="02" label="Clear reasoning" />
            <SignalLabel index="03" label="Easier alternatives" />
          </div>
        </div>
      </section>

      <section id="plan" className="scroll-mt-24">
        <div className="mb-5 flex flex-col justify-between gap-2 sm:flex-row sm:items-end">
          <div>
            <p className="mb-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-ink-label">Plan a route</p>
            <h2 className="text-2xl font-semibold tracking-[-0.035em] text-ink-primary sm:text-3xl">Where are you headed?</h2>
          </div>
          <p className="max-w-md text-sm leading-6 text-ink-secondary">
            Enter two places. We’ll rank the available routes from least to most demanding.
          </p>
        </div>
        <div className="roam-reveal roam-enter-delay-1">
          <Suspense fallback={
            <div className="mx-auto max-w-4xl overflow-hidden rounded-roam-lg border border-card bg-card">
              <div className="h-[520px] animate-pulse bg-card-elevated/50" />
            </div>
          }>
            <RouteForm />
          </Suspense>
        </div>
      </section>
    </div>
  );
}

function SignalLabel({ index, label }: { index: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-2.5 whitespace-nowrap">
      <span className="font-mono text-[10px] text-accent">{index}</span>
      {label}
    </span>
  );
}
