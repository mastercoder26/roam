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
          <NavBar />
          <main className="mx-auto w-full max-w-4xl px-5 pb-24 pt-6">
            {children}
          </main>
        </body>
      </html>
    </ClerkProvider>
  );
}
