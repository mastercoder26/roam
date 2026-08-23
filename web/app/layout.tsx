import type { Metadata } from "next";
import { ClerkProvider } from "@clerk/nextjs";
import { NavBar } from "@/components/NavBar";
import "./globals.css";

export const metadata: Metadata = {
  title: "Roam — Route difficulty, explained",
  description:
    "A web demo of Roam's route-scoring engine: plan a drive, see what makes it demanding, and learn how driver coaching scores work.",
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
          colorPrimary: "rgb(5, 107, 235)",
          colorBackground: "rgb(30, 30, 30)",
          colorText: "rgb(241, 241, 241)",
          colorTextSecondary: "rgba(255, 255, 255, 0.6)",
          colorInputBackground: "rgb(36, 36, 36)",
          colorInputText: "rgb(241, 241, 241)",
          borderRadius: "16px",
        },
      }}
    >
      <html lang="en" className="dark">
        <body className="min-h-screen bg-canvas font-sans text-ink-primary antialiased">
          <aside className="border-b border-accent/25 bg-accent/[0.09] px-5 py-3">
            <div className="mx-auto flex max-w-4xl flex-col items-start justify-between gap-2.5 sm:flex-row sm:items-center">
              <p className="max-w-2xl text-[13px] leading-relaxed text-ink-secondary">
                <strong className="font-semibold text-ink-primary">Basic web demo:</strong>{" "}
                This is an extremely basic version of Roam. The full app is optimized for iOS and could not be deployed here. Watch the walkthrough to see every feature and the complete iOS experience.
              </p>
              <a
                href="https://youtu.be/4EA2f0rQKrM"
                target="_blank"
                rel="noreferrer"
                className="shrink-0 rounded-full bg-accent px-3.5 py-2 text-[12px] font-semibold text-white transition-transform hover:scale-[1.02] active:scale-[0.98]"
              >
                Watch all features ↗
              </a>
            </div>
          </aside>
          <NavBar />
          <main className="mx-auto w-full max-w-4xl px-5 pb-24 pt-6">
            {children}
          </main>
        </body>
      </html>
    </ClerkProvider>
  );
}
