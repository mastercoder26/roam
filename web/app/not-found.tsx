import Link from "next/link";
import { Card } from "@/components/ui/Card";

export default function NotFound() {
  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center px-4 py-12">
      <Card className="w-full max-w-lg border-2 border-ink-primary/20 p-6 sm:p-8">
        <div className="flex items-center gap-3 border-b border-ink-primary/10 pb-4">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-accent/10 text-accent">
            <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5" stroke="currentColor" strokeWidth="2">
              <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
              <line x1="12" y1="9" x2="12" y2="13" />
              <line x1="12" y1="17" x2="12.01" y2="17" />
            </svg>
          </span>
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-accent">
              404 / Not Found
            </p>
            <h2 className="text-xl font-black tracking-tight text-ink-primary">
              Page or Route Not Found
            </h2>
          </div>
        </div>

        <p className="mt-4 text-sm leading-6 text-ink-secondary">
          The requested route, URL, or feature page does not exist. Check the address or jump back to the live route planning engine.
        </p>

        <div className="mt-6 flex flex-wrap items-center gap-3">
          <Link
            href="/"
            className="roam-jiggle inline-flex items-center justify-center bg-accent px-5 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-white shadow-roam-md transition-transform active:scale-[0.97]"
          >
            Go to Route Planner
          </Link>
          <Link
            href="/driver-scoring"
            className="roam-jiggle inline-flex items-center justify-center border border-ink-primary/20 bg-card px-5 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-ink-primary transition-colors hover:border-ink-primary active:scale-[0.97]"
          >
            Driver Scoring
          </Link>
        </div>
      </Card>
    </div>
  );
}
