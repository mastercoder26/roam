import { RouteForm } from "@/components/route/RouteForm";

export default function HomePage() {
  return (
    <div className="flex flex-col gap-20 sm:gap-24">
      <section className="relative isolate min-h-[720px] lg:min-h-[680px]">
        <div className="roam-enter relative z-10 flex items-center justify-between border-t-2 border-ink-primary pt-3 text-[10px] font-bold uppercase tracking-[0.18em] text-ink-label">
          <span>Roam / Route intelligence</span>
          <span>Web edition · 01</span>
        </div>

        <div className="relative z-10 mt-9 lg:mt-12">
          <h1 className="roam-enter roam-enter-delay-1 max-w-5xl text-[clamp(4.1rem,11.5vw,8.8rem)] font-black leading-[0.82] tracking-[-0.068em] text-ink-primary">
            Read the road.
            <span className="block text-accent">Own the drive.</span>
          </h1>
        </div>

        <div className="roam-enter roam-enter-delay-2 mt-9 lg:absolute lg:right-0 lg:top-9 lg:z-0 lg:mt-0 lg:w-[57%]">
          <RouteSketch />
        </div>

        <div className="relative z-10 mt-8 grid gap-5 border-t border-ink-primary/20 pt-5 sm:grid-cols-[1fr_auto] lg:absolute lg:bottom-0 lg:left-0 lg:w-[46%]">
          <p className="roam-enter roam-enter-delay-3 max-w-md text-[17px] leading-7 text-ink-secondary">
            Traffic, weather, turns, speed, and road complexity—read before
            you leave, then explained without the mystery.
          </p>
          <div className="roam-enter roam-enter-delay-4 flex flex-wrap gap-x-5 gap-y-2 text-[10px] font-bold uppercase tracking-[0.13em] text-ink-primary sm:flex-col">
            <SignalLabel index="01" label="Traffic" />
            <SignalLabel index="02" label="Weather" />
            <SignalLabel index="03" label="Alternates" />
          </div>
        </div>
      </section>

      <section id="plan" className="scroll-mt-24">
        <div className="roam-reveal mb-9 grid gap-6 border-t-2 border-ink-primary pt-3 sm:grid-cols-[1fr_0.65fr] sm:items-end">
          <div>
            <p className="mb-4 text-[10px] font-bold uppercase tracking-[0.18em] text-accent">02 / Plan a route</p>
            <h2 className="text-[clamp(3.6rem,9vw,7rem)] font-black leading-[0.82] tracking-[-0.065em] text-ink-primary">
              Where to?
            </h2>
          </div>
          <p className="max-w-md text-sm leading-6 text-ink-secondary sm:justify-self-end">
            Type an address or start from where you are. Roam compares the
            available routes and puts the least demanding option first.
          </p>
        </div>
        <div className="roam-reveal roam-enter-delay-1">
          <RouteForm />
        </div>
      </section>
    </div>
  );
}

function SignalLabel({ index, label }: { index: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-2.5 whitespace-nowrap">
      <span className="text-accent">{index}</span>
      {label}
    </span>
  );
}

function RouteSketch() {
  return (
    <div className="roam-hover-lift route-grid relative min-h-[430px] overflow-hidden border-y-2 border-ink-primary/15 bg-card sm:min-h-[520px] lg:min-h-[610px]">
      <div className="absolute left-5 top-5 z-10 sm:left-7 sm:top-7">
        <p className="text-[9px] font-bold uppercase tracking-[0.18em] text-ink-label">Live route / 24 min</p>
        <p className="mt-1 text-sm font-black uppercase tracking-[-0.02em] text-ink-primary">Lakeview → Downtown</p>
      </div>
      <div className="absolute right-5 top-5 z-10 text-right sm:right-7 sm:top-7">
        <p className="text-[9px] font-bold uppercase tracking-[0.18em] text-ink-label">Difficulty</p>
        <p className="mt-1 text-sm font-black uppercase text-positive">Easy / 32</p>
      </div>

      <svg viewBox="0 0 520 420" className="absolute inset-0 h-full w-full scale-[1.07]" aria-hidden="true">
        <path d="M-20 340C72 300 90 230 154 238c79 10 70 91 154 80 85-12 65-97 146-123 37-12 60-5 90 8" fill="none" stroke="#18233C" strokeOpacity=".07" strokeWidth="36" />
        <path d="M-10 110c100 51 138 25 190 74 57 54 29 105 97 121 70 16 101-35 132-85 26-41 61-57 121-48" fill="none" stroke="#18233C" strokeOpacity=".06" strokeWidth="16" />
        <path className="roam-route-line" d="M88 355c28-64 8-111 57-147 50-36 100-1 142-41 30-29 15-72 58-100" fill="none" stroke="#2557F5" strokeWidth="8" strokeLinecap="round" />
        <path className="roam-route-dots" d="M88 355c28-64 8-111 57-147 50-36 100-1 142-41 30-29 15-72 58-100" fill="none" stroke="white" strokeOpacity=".4" strokeWidth="2" strokeDasharray="2 12" strokeLinecap="round" />
        <circle className="roam-route-start" cx="88" cy="355" r="14" fill="#FFFEFA" stroke="#2557F5" strokeWidth="7" />
        <g className="roam-route-end">
          <circle cx="345" cy="67" r="18" fill="#2557F5" />
          <path d="m337 66 6 6 11-13" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
        </g>
      </svg>

      <div className="absolute inset-x-0 bottom-0 grid grid-cols-3 border-t border-ink-primary/20 bg-card/90 backdrop-blur-sm">
        <SketchMetric label="Time" value="24 min" />
        <SketchMetric label="Traffic" value="Light" />
        <SketchMetric label="Weather" value="Clear" />
      </div>
    </div>
  );
}

function SketchMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="border-r border-ink-primary/15 px-4 py-3.5 last:border-r-0 sm:px-5">
      <p className="text-[9px] font-bold uppercase tracking-[0.16em] text-ink-label">{label}</p>
      <p className="mt-1 text-sm font-black uppercase text-ink-primary sm:text-base">{value}</p>
    </div>
  );
}
