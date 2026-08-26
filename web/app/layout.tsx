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
              <a href="https://youtu.be/4EA2f0rQKrM" target="_blank" rel="noreferrer" className="text-sm font-semibold text-accent hover:underline">
                Watch the iOS walkthrough ↗
              </a>
            </div>
          </footer>
        </body>
      </html>
    </ClerkProvider>
  );
}
