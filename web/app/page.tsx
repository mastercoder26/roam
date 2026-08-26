import { RouteForm } from "@/components/route/RouteForm";

export default function HomePage() {
  return (
    <div className="flex flex-col gap-12 sm:gap-16">
      <section className="grid items-center gap-9 lg:grid-cols-[1.03fr_0.97fr] lg:gap-12">
        <div className="relative z-10 flex flex-col items-start">
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-accent/20 bg-accent/[0.07] px-3 py-1.5 text-xs font-bold uppercase tracking-[0.12em] text-accent">
            <span className="h-1.5 w-1.5 rounded-full bg-accent" />
            Live route intelligence
          </div>
          <h1 className="max-w-[720px] text-display font-black text-ink-primary">
            Know the drive
            <span className="block text-accent">before you go.</span>
          </h1>
          <p className="mt-7 max-w-xl text-[17px] leading-7 text-ink-secondary sm:text-lg">
            Roam reads the road ahead—traffic, weather, turns, speed, and
            complexity—then explains how demanding your route may feel.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3 text-sm font-semibold text-ink-primary">
            <SignalLabel label="Live traffic" />
            <SignalLabel label="Weather context" />
            <SignalLabel label="Alternate routes" />
          </div>
        </div>

        <RouteSketch />
      </section>

      <section id="plan" className="scroll-mt-24">
        <div className="mb-6 flex flex-col justify-between gap-3 sm:flex-row sm:items-end">
          <div>
            <p className="mb-2 text-xs font-bold uppercase tracking-[0.14em] text-accent">Plan a route</p>
            <h2 className="text-3xl font-black tracking-[-0.04em] text-ink-primary sm:text-4xl">
              Where are you headed?
            </h2>
          </div>
          <p className="max-w-md text-sm leading-6 text-ink-secondary sm:text-right">
            Enter an address or use your current location. We&apos;ll compare the
            available routes and surface the easiest option first.
          </p>
        </div>
        <RouteForm />
      </section>
    </div>
  );
}

function SignalLabel({ label }: { label: string }) {
  return (
    <span className="inline-flex items-center gap-2">
      <svg viewBox="0 0 20 20" className="h-4 w-4 text-positive" aria-hidden="true">
        <circle cx="10" cy="10" r="9" fill="currentColor" opacity="0.14" />
        <path d="m6.4 10.2 2.2 2.2 5-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      {label}
    </span>
  );
}

function RouteSketch() {
  return (
    <div className="route-grid relative min-h-[390px] overflow-hidden rounded-[34px] border border-card bg-card shadow-roam-hero sm:min-h-[450px]">
      <div className="absolute inset-x-5 top-5 flex items-center justify-between rounded-2xl border border-card bg-card/90 px-4 py-3 shadow-roam backdrop-blur sm:inset-x-7 sm:top-7">
        <div>
          <p className="text-[10px] font-bold uppercase tracking-[0.14em] text-ink-label">Best route</p>
          <p className="mt-0.5 text-sm font-bold text-ink-primary">Lakeview → Downtown</p>
        </div>
        <span className="rounded-full bg-positive/10 px-3 py-1.5 text-xs font-bold text-positive">Easy · 32</span>
      </div>

      <svg viewBox="0 0 520 420" className="absolute inset-0 h-full w-full" aria-hidden="true">
        <path d="M-20 340C72 300 90 230 154 238c79 10 70 91 154 80 85-12 65-97 146-123 37-12 60-5 90 8" fill="none" stroke="#18233C" strokeOpacity=".07" strokeWidth="36" />
        <path d="M-10 110c100 51 138 25 190 74 57 54 29 105 97 121 70 16 101-35 132-85 26-41 61-57 121-48" fill="none" stroke="#18233C" strokeOpacity=".06" strokeWidth="16" />
        <path d="M88 355c28-64 8-111 57-147 50-36 100-1 142-41 30-29 15-72 58-100" fill="none" stroke="#2557F5" strokeWidth="8" strokeLinecap="round" />
        <path d="M88 355c28-64 8-111 57-147 50-36 100-1 142-41 30-29 15-72 58-100" fill="none" stroke="white" strokeOpacity=".4" strokeWidth="2" strokeDasharray="2 12" strokeLinecap="round" />
        <circle cx="88" cy="355" r="14" fill="#FFFEFA" stroke="#2557F5" strokeWidth="7" />
        <circle cx="345" cy="67" r="18" fill="#2557F5" />
        <path d="m337 66 6 6 11-13" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      </svg>

      <div className="absolute bottom-5 left-5 right-5 grid grid-cols-3 gap-2 sm:bottom-7 sm:left-7 sm:right-7 sm:gap-3">
        <SketchMetric label="Time" value="24 min" />
        <SketchMetric label="Traffic" value="Light" />
        <SketchMetric label="Weather" value="Clear" />
      </div>
    </div>
  );
}

function SketchMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-card bg-card/90 px-3 py-3 shadow-roam backdrop-blur sm:px-4">
      <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-ink-label">{label}</p>
      <p className="mt-1 text-sm font-black text-ink-primary sm:text-base">{value}</p>
    </div>
  );
}
