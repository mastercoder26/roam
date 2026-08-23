"use client";

import dynamic from "next/dynamic";
import type { Bounds } from "@/lib/types";

const InteractiveRouteMap = dynamic(
  () =>
    import("@/components/route/InteractiveRouteMap").then(
      (module) => module.InteractiveRouteMap
    ),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full items-center justify-center bg-card-elevated text-sm text-ink-secondary">
        Loading map…
      </div>
    ),
  }
);

export function RoutePolylinePreview({
  polyline,
  bounds,
  color,
}: {
  polyline: string;
  bounds: Bounds;
  color: string;
}) {
  return <InteractiveRouteMap polyline={polyline} bounds={bounds} color={color} />;
}
