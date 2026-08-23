import type { ReactNode } from "react";
import { Divider, InfoRow } from "@/components/info/InfoRow";
import { Card, Pill, SectionHeader } from "@/components/ui/Card";

export const metadata = {
  title: "Features — Roam",
};

const groups: Array<{
  title: string;
  subtitle: string;
  status?: "In this demo" | "iOS app";
  features: Array<{
    title: string;
    detail: string;
    tone: "accent" | "safety" | "positive" | "secondary";
    icon: ReactNode;
  }>;
}> = [
  {
    title: "Plan a route",
    subtitle: "Understand what a drive may demand before setting out.",
    status: "In this demo",
    features: [
      {
        title: "Live route difficulty",
        detail: "Score an origin and destination using route geometry, maneuvers, traffic-aware timing, weather, daylight, and available road context.",
        tone: "accent",
        icon: <RouteIcon />,
      },
      {
        title: "Route choices",
        detail: "Compare the primary route with returned alternatives, ranked easiest-first with distance, duration, reasons, demands, and uncertainty.",
        tone: "positive",
        icon: <ForkIcon />,
      },
      {
        title: "Departure comparisons",
        detail: "The iOS app can compare nearby departure times when live conditions are available, helping families avoid a more demanding window.",
        tone: "safety",
        icon: <ClockIcon />,
      },
      {
        title: "Transparent evidence",
        detail: "See which live sources contributed, how much of the route they covered, and where the strongest difficulty hotspots appear.",
        tone: "accent",
        icon: <LayersIcon />,
      },
    ],
  },
  {
    title: "Build route readiness",
    subtitle: "Turn recorded experience into specific, explainable practice guidance.",
    status: "iOS app",
    features: [
      {
        title: "Demand-by-demand readiness",
        detail: "Compare eight route demands—such as after-dark driving, merges, traffic, faster roads, and weather—with matching measured experience.",
        tone: "safety",
        icon: <GaugeIcon />,
      },
      {
        title: "Guided practice plans",
        detail: "Queue a route, identify experience gaps, and practice with an adult rather than relying on a single overall grade.",
        tone: "positive",
        icon: <TargetIcon />,
      },
      {
        title: "Route familiarity",
        detail: "Privately compare a planned route with directionally aligned local traces while excluding parallel roads and long GPS gaps.",
        tone: "accent",
        icon: <MapIcon />,
      },
      {
        title: "Shared routes",
        detail: "Import shared route links into a durable inbox, then review or retry them without silently losing a plan.",
        tone: "secondary",
        icon: <ShareIcon />,
      },
    ],
  },
  {
    title: "Record and coach",
    subtitle: "A manually controlled drive session using the sensors already in an iPhone.",
    status: "iOS app",
    features: [
      {
        title: "Manual drive recording",
        detail: "Start before leaving and end after parking. Roam measures elapsed time, accepted GPS fixes, distance, speed, and phone motion during the session.",
        tone: "accent",
        icon: <RecordIcon />,
      },
      {
        title: "Coaching events",
        detail: "Flag hard braking, rapid acceleration, sharp cornering, and sustained abrupt phone movement using quality-gated GPS and motion evidence.",
        tone: "safety",
        icon: <PulseIcon />,
      },
      {
        title: "Honest confidence",
        detail: "Label each drive Preliminary, Useful, or Strong based on trace duration, distance, accepted GPS fixes, motion samples, and rejected-location rate.",
        tone: "positive",
        icon: <SealIcon />,
      },
      {
        title: "Private replay",
        detail: "Keep the local GPS trace and coaching events available for review without treating the result as proof that a driver is safe.",
        tone: "secondary",
        icon: <ReplayIcon />,
      },
    ],
  },
  {
    title: "Track progress",
    subtitle: "Evidence over time, weighted by quality instead of raw activity alone.",
    status: "iOS app",
    features: [
      {
        title: "Overall coaching score",
        detail: "Combine qualifying drives using route adjustment, distance weighting, confidence weighting, and a 120-day recency half-life.",
        tone: "accent",
        icon: <ChartIcon />,
      },
      {
        title: "Measured experience",
        detail: "Track validated miles, after-dark miles, 45+ mph miles, continuous-trace coverage, and qualifying drive time.",
        tone: "positive",
        icon: <RoadIcon />,
      },
      {
        title: "Eight-week history",
        detail: "Review recent evidence and trends without letting one unusually long or unusually good drive dominate the story.",
        tone: "accent",
        icon: <CalendarIcon />,
      },
      {
        title: "Lifetime profile",
        detail: "See locally recorded totals alongside a self-declared display name and licensing stage—neither identity field changes any score.",
        tone: "secondary",
        icon: <PersonIcon />,
      },
    ],
  },
  {
    title: "Drive-aware integrations",
    subtitle: "Useful information in the right place, with deliberate limits.",
    status: "iOS app",
    features: [
      {
        title: "Live Activity",
        detail: "While a manual drive is active, show elapsed time, speed, distance, and event count without exposing a route, address, or raw location.",
        tone: "accent",
        icon: <ActivityIcon />,
      },
      {
        title: "CarPlay dashboard",
        detail: "Mirror active-drive information on a compatible head unit while keeping start and stop controls on the iPhone.",
        tone: "positive",
        icon: <CarIcon />,
      },
      {
        title: "Navigation handoff",
        detail: "Move from planning to the system navigation experience rather than asking someone to interact with Roam while driving.",
        tone: "accent",
        icon: <ArrowIcon />,
      },
      {
        title: "Privacy by design",
        detail: "Keep manual drive scoring on-device and minimize what leaves the phone; profile identity is excluded from every score.",
        tone: "secondary",
        icon: <LockIcon />,
      },
    ],
  },
];

export default function FeaturesPage() {
  return (
    <div className="flex flex-col gap-9">
      <header className="flex flex-col gap-3">
        <div className="flex h-[52px] w-[52px] items-center justify-center rounded-roam-sm bg-accent/12 text-accent">
          <GridIcon className="h-6 w-6" />
        </div>
        <div className="flex flex-wrap items-center gap-2.5">
          <h1 className="text-[26px] font-bold tracking-[-0.4px] text-ink-primary">
            Everything Roam can do
          </h1>
          <Pill tone="accent">Product map</Pill>
        </div>
        <p className="max-w-2xl text-[15px] leading-relaxed text-ink-secondary">
          Roam connects route planning, private driving evidence, and guided
          practice into one coaching experience. Route analysis is playable in
          this web demo; sensor-based features live in the native iOS app.
        </p>
      </header>

      {groups.map((group) => (
        <section key={group.title}>
          <div className="mb-3 flex items-end justify-between gap-4">
            <SectionHeader title={group.title} subtitle={group.subtitle} />
            {group.status ? (
              <span className="mb-3 shrink-0 text-[11px] font-bold uppercase tracking-[0.9px] text-ink-label">
                {group.status}
              </span>
            ) : null}
          </div>
          <Card className="!py-1">
            {group.features.map((feature, index) => (
              <div key={feature.title}>
                <InfoRow {...feature} />
                {index < group.features.length - 1 ? <Divider /> : null}
              </div>
            ))}
          </Card>
        </section>
      ))}

      <Card className="border-safety/25 bg-safety/[0.06]">
        <div className="flex items-start gap-3.5">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-roam-tiny bg-safety/12 text-safety">
            <ShieldIcon className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-[15px] font-semibold text-ink-primary">
              Planning and coaching—not a safety verdict
            </h2>
            <p className="mt-1 text-[13px] leading-relaxed text-ink-secondary">
              Roam cannot guarantee that a route or person is safe, detect a
              crash, or replace local laws, licensing restrictions, supervision,
              and judgment. Do not operate the app while driving.
            </p>
          </div>
        </div>
      </Card>
    </div>
  );
}

function IconBase({ children, className = "h-4 w-4" }: { children: ReactNode; className?: string }) {
  return <svg viewBox="0 0 24 24" fill="none" className={className} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{children}</svg>;
}
function RouteIcon() { return <IconBase><circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M8 18h2a3 3 0 0 0 3-3V9a3 3 0 0 1 3-3"/></IconBase>; }
function ForkIcon() { return <IconBase><path d="M12 21V10m0 0 5-5m-5 5L7 5"/><path d="m15 5 2-2 2 2M5 5l2-2 2 2"/></IconBase>; }
function ClockIcon() { return <IconBase><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></IconBase>; }
function LayersIcon() { return <IconBase><path d="m12 3-9 5 9 5 9-5-9-5Z"/><path d="m3 12 9 5 9-5M3 16l9 5 9-5"/></IconBase>; }
function GaugeIcon() { return <IconBase><path d="M4 18a8 8 0 1 1 16 0"/><path d="m12 14 4-4"/><path d="M7 18h10"/></IconBase>; }
function TargetIcon() { return <IconBase><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/></IconBase>; }
function MapIcon() { return <IconBase><path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6Z"/><path d="M9 3v15m6-12v15"/></IconBase>; }
function ShareIcon() { return <IconBase><circle cx="18" cy="5" r="2"/><circle cx="6" cy="12" r="2"/><circle cx="18" cy="19" r="2"/><path d="m8 11 8-5M8 13l8 5"/></IconBase>; }
function RecordIcon() { return <IconBase><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/></IconBase>; }
function PulseIcon() { return <IconBase><path d="M3 12h4l2-6 4 12 2-6h6"/></IconBase>; }
function SealIcon() { return <IconBase><path d="m12 3 2 2.2 3-.2.8 2.9 2.7 1.5-1.1 2.8 1.1 2.8-2.7 1.5-.8 2.9-3-.2L12 21l-2-2.2-3 .2-.8-2.9-2.7-1.5 1.1-2.8-1.1-2.8 2.7-1.5L7 5l3 .2L12 3Z"/><path d="m9 12 2 2 4-4"/></IconBase>; }
function ReplayIcon() { return <IconBase><path d="M4 11a8 8 0 1 1 2 6"/><path d="M4 5v6h6"/></IconBase>; }
function ChartIcon() { return <IconBase><path d="M4 20V10m6 10V4m6 16v-7m4 7H2"/></IconBase>; }
function RoadIcon() { return <IconBase><path d="m8 3-3 18m11-18 3 18M12 4v3m0 4v3m0 4v3"/></IconBase>; }
function CalendarIcon() { return <IconBase><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M8 3v4m8-4v4M3 10h18"/></IconBase>; }
function PersonIcon() { return <IconBase><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></IconBase>; }
function ActivityIcon() { return <IconBase><rect x="3" y="4" width="18" height="16" rx="4"/><path d="M7 12h3l2-4 2 8 2-4h2"/></IconBase>; }
function CarIcon() { return <IconBase><path d="m5 16-1-4 2-5h12l2 5-1 4H5Z"/><path d="M7 16v2m10-2v2M6 12h12"/><circle cx="8" cy="14" r="1" fill="currentColor"/><circle cx="16" cy="14" r="1" fill="currentColor"/></IconBase>; }
function ArrowIcon() { return <IconBase><path d="M5 12h14m-5-5 5 5-5 5"/></IconBase>; }
function LockIcon() { return <IconBase><rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></IconBase>; }
function GridIcon({ className }: { className?: string }) { return <IconBase className={className}><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></IconBase>; }
function ShieldIcon({ className }: { className?: string }) { return <IconBase className={className}><path d="M12 3 5 6v5c0 4.6 2.8 8 7 10 4.2-2 7-5.4 7-10V6l-7-3Z"/><path d="M12 8v5m0 3h.01"/></IconBase>; }
