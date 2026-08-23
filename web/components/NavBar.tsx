"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  SignedIn,
  SignedOut,
  SignInButton,
  UserButton,
} from "@clerk/nextjs";

const TABS = [
  { href: "/", label: "Routes", icon: RoutesIcon },
  { href: "/driver-scoring", label: "Driver Scoring", icon: SteeringWheelIcon },
  { href: "/features", label: "Features", icon: FeaturesIcon },
];

export function NavBar() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-30 border-b border-card bg-canvas/85 backdrop-blur-lg">
      <div className="mx-auto flex max-w-4xl items-center justify-between gap-3 px-5 py-3">
        <Link href="/" className="flex items-center gap-2 shrink-0">
          <span
            className="flex h-8 w-8 items-center justify-center rounded-full text-[15px] font-bold text-white"
            style={{ background: "linear-gradient(145deg, rgb(5,107,235), rgb(20,60,150))" }}
          >
            R
          </span>
          <span className="text-[17px] font-bold tracking-[-0.3px] text-ink-primary">
            Roam
          </span>
        </Link>

        <nav className="flex flex-1 items-center justify-center gap-1 rounded-full border border-card bg-card p-1">
          {TABS.map((tab) => {
            const active =
              tab.href === "/" ? pathname === "/" : pathname?.startsWith(tab.href);
            const Icon = tab.icon;
            return (
              <Link
                key={tab.href}
                href={tab.href}
                className={`flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[13px] font-semibold transition-colors ${
                  active
                    ? "bg-accent text-white"
                    : "text-ink-secondary hover:text-ink-primary"
                }`}
              >
                <Icon className="h-4 w-4 shrink-0" />
                <span className="hidden sm:inline">{tab.label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="flex shrink-0 items-center gap-3">
          <SignedOut>
            <SignInButton mode="modal">
              <button className="rounded-full bg-ink-primary px-4 py-2 text-[13px] font-semibold text-canvas transition-transform active:scale-95">
                Sign in
              </button>
            </SignInButton>
          </SignedOut>
          <SignedIn>
            <UserButton
              appearance={{
                elements: { avatarBox: "h-8 w-8" },
              }}
            />
          </SignedIn>
        </div>
      </div>
    </header>
  );
}

function RoutesIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path
        d="M5 20c3-6 3-9 0-11m14 11c-3-6-3-9 0-11M9 4l3 3 3-3M9 20l3-3 3 3"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="12" cy="9" r="2.3" stroke="currentColor" strokeWidth="1.8" />
    </svg>
  );
}

function SteeringWheelIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <circle cx="12" cy="12" r="8.5" stroke="currentColor" strokeWidth="1.8" />
      <circle cx="12" cy="12" r="2" stroke="currentColor" strokeWidth="1.8" />
      <path
        d="M12 5.2V10M6.3 15.8l3.6-2.6M17.7 15.8l-3.6-2.6"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

function FeaturesIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <rect x="4" y="4.5" width="16" height="3.6" rx="1.4" stroke="currentColor" strokeWidth="1.8" />
      <rect x="4" y="10.2" width="16" height="3.6" rx="1.4" stroke="currentColor" strokeWidth="1.8" />
      <rect x="4" y="15.9" width="10" height="3.6" rx="1.4" stroke="currentColor" strokeWidth="1.8" />
    </svg>
  );
}
