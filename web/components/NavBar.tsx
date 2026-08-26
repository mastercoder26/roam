"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  SignedIn,
  SignedOut,
  SignInButton,
  UserButton,
} from "@clerk/nextjs";
import { BrandLogo } from "@/components/BrandLogo";

const TABS = [
  { href: "/", label: "Routes", icon: RoutesIcon },
  { href: "/driver-scoring", label: "Driver Scoring", icon: SteeringWheelIcon },
  { href: "/features", label: "Features", icon: FeaturesIcon },
];

export function NavBar() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-30 border-b border-ink-primary/10 bg-canvas/90 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-5 px-5 py-4 sm:px-8">
        <BrandLogo compact />

        <nav aria-label="Primary navigation" className="ml-auto flex items-center justify-center gap-1 sm:gap-7">
          {TABS.map((tab) => {
            const active =
              tab.href === "/" ? pathname === "/" : pathname?.startsWith(tab.href);
            const Icon = tab.icon;
            return (
              <Link
                key={tab.href}
                href={tab.href}
                aria-label={tab.label}
                aria-current={active ? "page" : undefined}
                className={`roam-jiggle relative flex items-center gap-1.5 px-2 py-2 text-[11px] font-bold uppercase tracking-[0.1em] transition-colors duration-200 sm:px-0 ${
                  active
                    ? "text-accent after:absolute after:inset-x-0 after:-bottom-0.5 after:h-0.5 after:bg-accent"
                    : "text-ink-primary hover:text-accent"
                }`}
              >
                <Icon className="h-4 w-4 shrink-0 sm:hidden" />
                <span className="hidden sm:inline">{tab.label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="flex shrink-0 items-center gap-3">
          <SignedOut>
            <SignInButton mode="modal">
              <button className="roam-jiggle border border-ink-primary bg-ink-primary px-3.5 py-2.5 text-[11px] font-bold uppercase tracking-[0.08em] text-white transition-colors hover:bg-accent hover:border-accent active:scale-[0.97] sm:px-5">
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
