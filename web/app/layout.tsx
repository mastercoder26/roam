import type { Metadata } from "next";
import { ClerkProvider } from "@clerk/nextjs";
import { NavBar } from "@/components/NavBar";
import { BrandLogo } from "@/components/BrandLogo";
import "leaflet/dist/leaflet.css";
import "./globals.css";

export const metadata: Metadata = {
  title: "Roam — Route difficulty, explained",
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
          <aside className="border-b border-white/10 bg-ink-primary px-5 py-2.5 text-white">
            <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-center gap-x-2 gap-y-1 text-center text-xs sm:text-sm">
              <span className="text-white/70">This is an extremely basic web demo. See the complete Roam experience.</span>
              <a
                href="https://youtu.be/4EA2f0rQKrM"
                target="_blank"
                rel="noreferrer"
                className="roam-jiggle inline-flex items-center gap-1 font-bold text-white underline decoration-white/40 underline-offset-4 transition-colors hover:decoration-white"
              >
                Watch the iOS walkthrough
                <span aria-hidden="true">↗</span>
              </a>
            </div>
          </aside>
          <NavBar />
          <main className="mx-auto w-full max-w-6xl px-5 pb-20 pt-8 sm:px-8 sm:pt-12">
            {children}
          </main>
          <footer className="border-t border-card bg-card/60 px-5 py-8">
            <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-5 sm:flex-row sm:items-center">
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
