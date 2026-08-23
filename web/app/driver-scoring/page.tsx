import { Card, SectionHeader } from "@/components/ui/Card";
import { InfoRow, Divider } from "@/components/info/InfoRow";

export const metadata = {
  title: "How driver scoring works — Roam",
};

export default function DriverScoringPage() {
  return (
    <div className="flex flex-col gap-9">
      <header className="flex flex-col gap-3">
        <div className="flex h-[52px] w-[52px] items-center justify-center rounded-roam-sm bg-accent/12 text-accent">
          <SteeringWheelIcon className="h-6 w-6" />
        </div>
        <h1 className="text-[26px] font-bold tracking-[-0.4px] text-ink-primary">
          How driver scoring works
        </h1>
        <p className="max-w-2xl text-[15px] leading-relaxed text-ink-secondary">
          Roam&apos;s Drive tab turns a manually started session into a private,
          on-device coaching score. Nothing here is a safety system or a
          guarantee — it&apos;s feedback built entirely from measured GPS speed
          changes and phone motion.
        </p>
      </header>

      <Section title="What a drive session measures">
        <Card className="!py-1">
          <InfoRow
            tone="accent"
            icon={<LocationIcon className="h-4 w-4" />}
            title="Route trace"
            detail="GPS continuity, distance, speed, duration, and overlap with a planned practice route."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<SpeedIcon className="h-4 w-4" />}
            title="Speed changes"
            detail="Measured changes in accepted GPS speed can identify rapid acceleration and hard braking events."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<TurnIcon className="h-4 w-4" />}
            title="Turning motion"
            detail="Course change and gravity-free Core Motion readings can identify sharper cornering when sensor quality is sufficient."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<ChartIcon className="h-4 w-4" />}
            title="Experience coverage"
            detail="Qualifying miles can contribute to after-dark, faster-road, continuous-driving, and weekly progress totals."
          />
        </Card>
      </Section>

      <Section
        title="How one drive is scored"
        subtitle="Every drive starts at 100 and loses points for coaching events, normalized per 10 miles so a short trip and a long trip are judged fairly."
      >
        <Card>
          <div className="grid gap-3 sm:grid-cols-2">
            <EventStat
              title="Hard braking"
              detail="Deceleration ≥ 3.2 m/s² while moving 4+ m/s."
              weight="-3.5 pts / 10 mi"
            />
            <EventStat
              title="Rapid acceleration"
              detail="Acceleration ≥ 2.8 m/s² while moving 4+ m/s."
              weight="-2.5 pts / 10 mi"
            />
            <EventStat
              title="Sharp corner"
              detail="Course change ≥ 28°/s while moving 6+ m/s, with a reliable GPS heading."
              weight="-2.25 pts / 10 mi"
            />
            <EventStat
              title="Possible phone handling"
              detail="A sustained acceleration-and-rotation pattern while the vehicle is moving — a single bump is ignored."
              weight="-0.75 pts / 10 mi"
            />
          </div>
          <p className="mt-4 text-[12.5px] leading-relaxed text-ink-tertiary">
            Penalties are capped at 55 points and the floor is 20, so one rough
            trip is never scored as a zero. GPS-derived events count on their
            own; motion data that corroborates a GPS event upgrades its
            provenance from &ldquo;GPS speed&rdquo; to &ldquo;GPS + motion.&rdquo;
          </p>
        </Card>
      </Section>

      <Section
        title="Confidence tiers"
        subtitle="A score is only as trustworthy as the data behind it, so every drive is labeled honestly."
      >
        <Card className="!py-1">
          <InfoRow
            tone="positive"
            icon={<SealIcon className="h-4 w-4" />}
            title="Strong sample"
            badge="High"
            detail="At least 5 minutes of usable trace, 2+ miles, 24+ accepted GPS fixes, and 1,200+ motion samples."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<HalfCircleIcon className="h-4 w-4" />}
            title="Useful sample"
            badge="Medium"
            detail="At least 90 seconds of usable trace, 0.5+ miles, 8+ accepted GPS fixes, and 240+ motion samples."
          />
          <Divider />
          <InfoRow
            tone="secondary"
            icon={<ExclamationIcon className="h-4 w-4" />}
            title="Preliminary"
            badge="Low"
            detail="Short or sparse drives, or drives where over half of delivered GPS fixes had to be rejected for accuracy."
          />
        </Card>
      </Section>

      <Section
        title="The overall coaching score"
        subtitle="Progress and Profile combine many drives into one evidence-weighted number — never a single trip."
      >
        <Card className="!py-1">
          <InfoRow
            tone="accent"
            icon={<GaugeIcon className="h-4 w-4" />}
            title="Route-adjusted"
            detail="Each qualifying drive's sensor score is nudged by that trip's independently analyzed route difficulty — a smooth drive on a demanding route counts a bit more than the same smoothness on an easy one."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<RulerIcon className="h-4 w-4" />}
            title="Distance-weighted"
            detail="Weight grows with the square root of measured miles, so one unusually long drive can't dominate a broad, consistent history."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<ClockIcon className="h-4 w-4" />}
            title="Recency-weighted"
            detail="Older drives fade on a 120-day half-life, so the score reflects how someone drives now, not only when they started."
          />
          <Divider />
          <InfoRow
            tone="accent"
            icon={<CheckSealIcon className="h-4 w-4" />}
            title="Quality-gated"
            detail="Only medium- or high-confidence drives are included at all, and high-confidence drives count more than medium."
          />
        </Card>
        <div className="mt-3 flex flex-wrap gap-2.5">
          {[
            { title: "Building", detail: "Fewer than 3 analyzed drives or 10 miles." },
            { title: "Growing", detail: "3+ drives and 10+ miles." },
            { title: "Established", detail: "8+ drives and 30+ miles." },
          ].map((tier) => (
            <div
              key={tier.title}
              className="flex-1 min-w-[140px] rounded-roam-sm border border-card bg-card-elevated px-3.5 py-3"
            >
              <span className="text-[13px] font-semibold text-ink-primary">
                {tier.title}
              </span>
              <p className="mt-0.5 text-[12px] text-ink-secondary">
                {tier.detail}
              </p>
            </div>
          ))}
        </div>
      </Section>

      <Section
        title="“Can I drive this?” route readiness"
        subtitle="Before showing a verdict, Roam requires a real base of recorded experience — not just a good-looking score."
      >
        <Card className="!py-1">
          <InfoRow
            tone="safety"
            icon={<HistoryIcon className="h-4 w-4" />}
            title="History gate"
            detail="At least 3 qualifying drives on 3 different days, 15+ miles of validated trace, and 45+ minutes of continuous driving before any route gets compared at all."
          />
          <Divider />
          <InfoRow
            tone="safety"
            icon={<CompareIcon className="h-4 w-4" />}
            title="Demand-by-demand comparison"
            detail="Each of the route's 8 demand categories (after-dark, fast roads, merges, intersections, weather, sustained drive, traffic, road conditions) is checked against matching recorded exposure — after-dark miles against after-dark miles, not a single overall grade."
          />
          <Divider />
          <InfoRow
            tone="safety"
            icon={<MapPinIcon className="h-4 w-4" />}
            title="Route familiarity"
            detail="On-device GPS overlap with saved, directionally aligned traces — parallel roads and long gaps are excluded — contributes to, but never replaces, the demand comparison."
          />
        </Card>
        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
          <VerdictChip tone="positive" title="Looks like a match" />
          <VerdictChip tone="safety" title="Practice this with an adult" />
          <VerdictChip tone="secondary" title="Need more recorded experience" />
        </div>
      </Section>

      <Section title="Privacy">
        <Card>
          <div className="flex items-start gap-3.5">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-roam-tiny bg-accent/12 text-accent">
              <LockIcon className="h-5 w-5" />
            </div>
            <div className="flex flex-col gap-2">
              <p className="text-[13.5px] leading-relaxed text-ink-secondary">
                Manual driving scores stay on the device. Only after a
                completed drive with a continuous trace does Roam send the
                measured start and end <em>coordinates</em> — never an address
                or the recorded route geometry — to the route-analysis
                service, and it stores only the resulting compact difficulty
                snapshot locally.
              </p>
              <p className="text-[13px] font-semibold text-ink-primary">
                A driver&apos;s name and licensing stage are self-declared and
                never change a route score or a driving score.
              </p>
            </div>
          </div>
        </Card>
      </Section>

      <Section title="Important limits">
        <Card className="flex flex-col gap-2.5">
          {[
            "Roam is a planning and coaching tool, not a safety guarantee.",
            "A drive score is coaching feedback, not proof a person or route is safe.",
            "The phone-motion detector never identifies handheld use — it only flags a sustained, abrupt movement pattern.",
            "Follow local laws, license restrictions, supervision rules, and your own judgment.",
          ].map((text) => (
            <div key={text} className="flex items-start gap-2.5">
              <CheckIcon className="mt-0.5 h-4 w-4 shrink-0 text-ink-secondary" />
              <p className="text-[13.5px] leading-relaxed text-ink-secondary">
                {text}
              </p>
            </div>
          ))}
        </Card>
      </Section>
    </div>
  );
}

function Section({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <section>
      <SectionHeader title={title} subtitle={subtitle} />
      {children}
    </section>
  );
}

function EventStat({
  title,
  detail,
  weight,
}: {
  title: string;
  detail: string;
  weight: string;
}) {
  return (
    <div className="rounded-roam-sm border border-card bg-card-elevated p-3.5">
      <div className="flex items-center justify-between gap-2">
        <span className="text-[13.5px] font-semibold text-ink-primary">
          {title}
        </span>
        <span className="rounded-full bg-danger/15 px-2 py-0.5 text-[11px] font-bold text-danger">
          {weight}
        </span>
      </div>
      <p className="mt-1 text-[12.5px] leading-relaxed text-ink-secondary">
        {detail}
      </p>
    </div>
  );
}

function VerdictChip({
  tone,
  title,
}: {
  tone: "positive" | "safety" | "secondary";
  title: string;
}) {
  const toneClass: Record<string, string> = {
    positive: "bg-positive/12 text-positive",
    safety: "bg-safety/12 text-safety",
    secondary: "bg-white/10 text-ink-secondary",
  };
  return (
    <span
      className={`flex-1 rounded-roam-sm px-3.5 py-2.5 text-center text-[13px] font-semibold ${toneClass[tone]}`}
    >
      {title}
    </span>
  );
}

// --- Icons (kept minimal/inline; no icon package dependency) ---

function SteeringWheelIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <circle cx="12" cy="12" r="8.5" stroke="currentColor" strokeWidth="1.8" />
      <circle cx="12" cy="12" r="2" stroke="currentColor" strokeWidth="1.8" />
      <path d="M12 5.2V10M6.3 15.8l3.6-2.6M17.7 15.8l-3.6-2.6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}
function LocationIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M12 21s7-6.1 7-11.5A7 7 0 0 0 5 9.5C5 14.9 12 21 12 21Z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
      <circle cx="12" cy="9.5" r="2.4" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  );
}
function SpeedIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M4 15a8 8 0 1 1 16 0" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      <path d="M12 15 16 9" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}
function TurnIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M6 5v7a4 4 0 0 0 4 4h8m0 0-3-3m3 3-3 3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function ChartIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M4 19V5M4 19h16M8 16v-4m4 4V8m4 8v-6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function SealIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M12 3 20 7v5c0 5-3.4 8.4-8 9-4.6-.6-8-4-8-9V7l8-4Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      <path d="m9 12 2 2 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function HalfCircleIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <circle cx="12" cy="12" r="8.5" stroke="currentColor" strokeWidth="1.7" />
      <path d="M12 3.5A8.5 8.5 0 0 1 12 20.5Z" fill="currentColor" />
    </svg>
  );
}
function ExclamationIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <circle cx="12" cy="12" r="8.5" stroke="currentColor" strokeWidth="1.7" />
      <path d="M12 7.5v5.5M12 16.5v.2" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />
    </svg>
  );
}
function GaugeIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M4 16a8 8 0 1 1 16 0" stroke="currentColor" strokeWidth="1.7" />
      <circle cx="12" cy="16" r="1.6" fill="currentColor" />
      <path d="M12 16 15 11" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}
function RulerIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <rect x="3.5" y="9" width="17" height="6" rx="1.4" transform="rotate(-8 12 12)" stroke="currentColor" strokeWidth="1.6" />
      <path d="M8 10.5v2M11.5 10v2M15 9.5v2" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}
function ClockIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <circle cx="12" cy="12" r="8.2" stroke="currentColor" strokeWidth="1.7" />
      <path d="M12 7.5V12l3 2" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function CheckSealIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="m4 12 5-8 6 2 5 5-2 8-8 2-6-4Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="m9 12.5 2 2 4-4.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function HistoryIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M4 12a8 8 0 1 0 2.6-5.9" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      <path d="M4 5v4h4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M12 8v4l3 2" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function CompareIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M8 4v13M8 17l-3-3M8 17l3-3M16 20V7M16 7l-3 3M16 7l3 3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
function MapPinIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="M12 21s7-6.1 7-11.5A7 7 0 0 0 5 9.5C5 14.9 12 21 12 21Z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
      <circle cx="12" cy="9.5" r="2.4" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  );
}
function LockIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <rect x="5" y="10.5" width="14" height="9.5" rx="2" stroke="currentColor" strokeWidth="1.7" />
      <path d="M8 10.5V7.5a4 4 0 1 1 8 0v3" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  );
}
function CheckIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className}>
      <path d="m5 12.5 4.5 4.5L19 7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
