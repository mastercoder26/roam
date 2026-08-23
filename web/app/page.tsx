import { RouteForm } from "@/components/route/RouteForm";

export default function HomePage() {
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1.5">
        <h1 className="text-[28px] font-bold tracking-[-0.4px] text-ink-primary">
          Where to?
        </h1>
        <p className="text-[15px] text-ink-secondary">
          Roam scores a planned route&apos;s driving difficulty using live
          traffic, weather, road, and maneuver data — the same engine and
          backend as the iOS app.
        </p>
      </div>
      <RouteForm />
    </div>
  );
}
