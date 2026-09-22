import type { Metadata } from "next";
import { ClerkProvider } from "@clerk/nextjs";
import { NavBar } from "@/components/NavBar";
import { BrandLogo } from "@/components/BrandLogo";
import "leaflet/dist/leaflet.css";
import "./globals.css";

export const metadata: Metadata = {
  title: "Roam: Route difficulty, explained",
  description:
    "A web demo of Roam's route-scoring engine: plan a drive, see what makes it demanding, and learn how driver coaching scores work.",
  icons: { icon: "/brand/roam-icon.png", apple: "/brand/roam-icon.png" },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <ClerkProvider
      appearance={{
        variables: {
          colorPrimary: "#2557F5",
          colorBackground: "#FFFEFA",
          colorText: "#18233C",
          colorTextSecondary: "#626A78",
          colorInputBackground: "#F7F4EC",
          colorInputText: "#18233C",
          borderRadius: "16px",
        },
      }}
    >
      <html lang="en" data-scroll-behavior="smooth">
        <body className="min-h-screen bg-canvas font-sans text-ink-primary antialiased">
          <aside className="border-b border-card bg-card px-5 py-2 text-ink-primary">
            <div className="mx-auto flex max-w-7xl items-center justify-center gap-2 text-center text-xs">
              <span className="inline-block h-1.5 w-1.5 rounded-full bg-positive" aria-hidden="true" />
              <span className="text-ink-secondary">Roam for iPhone</span>
              <a
                href="https://youtu.be/b0pFSwxqZD0"
                target="_blank"
                rel="noreferrer"
                className="roam-jiggle inline-flex items-center gap-1 font-semibold text-ink-primary underline decoration-card-strong underline-offset-4 transition-colors hover:decoration-ink-primary"
              >
                Watch the walkthrough
                <span aria-hidden="true">↗</span>
              </a>
            </div>
          </aside>
          <NavBar />
          <main className="mx-auto w-full max-w-7xl px-5 pb-24 pt-8 sm:px-8 sm:pt-12">
            {children}
          </main>
          <footer className="border-t border-card bg-card px-5 py-8">
            <div className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-5 sm:flex-row sm:items-center">
              <div className="flex items-center gap-4">
                <BrandLogo compact />
                <span className="hidden h-5 w-px bg-card-strong sm:block" />
                <p className="text-xs text-ink-secondary">Route planning and coaching, not a safety guarantee.</p>
              </div>
            </div>
          </footer>
        </body>
      </html>
    </ClerkProvider>
  );
}
