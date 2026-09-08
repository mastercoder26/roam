"use client";

import { useEffect } from "react";
import Link from "next/link";
import { Card } from "@/components/ui/Card";

export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log client error for observability
    console.error("Roam client error caught by application boundary:", error);
  }, [error]);

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center px-4 py-12">
      <Card className="w-full max-w-lg border-2 border-ink-primary/20 p-6 sm:p-8">
        <div className="flex items-center gap-3 border-b border-ink-primary/10 pb-4">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-danger/10 text-danger">
            <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="9" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
          </span>
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-danger">
              Application Error
            </p>
            <h2 className="text-xl font-black tracking-tight text-ink-primary">
              Something went wrong
            </h2>
          </div>
        </div>

        <p className="mt-4 text-sm leading-6 text-ink-secondary">
          {error.message || "An unexpected error occurred while rendering this route. Your data and session are intact."}
        </p>

        {error.digest ? (
          <p className="mt-2 text-xs font-mono text-ink-tertiary">
            Error digest: {error.digest}
          </p>
        ) : null}

        <div className="mt-6 flex flex-wrap items-center gap-3">
          <button
            type="button"
            onClick={reset}
            className="roam-jiggle inline-flex items-center justify-center bg-accent px-5 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-white shadow-roam-md transition-transform active:scale-[0.97]"
          >
            Try again
          </button>
          <Link
            href="/"
            className="roam-jiggle inline-flex items-center justify-center border border-ink-primary/20 bg-card px-5 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-ink-primary transition-colors hover:border-ink-primary active:scale-[0.97]"
          >
            Return to Route Planner
          </Link>
        </div>
      </Card>
    </div>
  );
}
