"use client";

import { useMemo } from "react";
import { decodePolyline } from "@/lib/polyline";
import type { Bounds } from "@/lib/types";

// No Maps SDK/API key is used here on purpose: the route geometry the
// backend returns is projected locally with a simple equirectangular
// projection scaled to the route bounds, so the shape (not a basemap) is
// what's shown.
export function RoutePolylinePreview({
  polyline,
  bounds,
  color,
}: {
  polyline: string;
  bounds: Bounds;
  color: string;
}) {
  const path = useMemo(() => {
    const points = decodePolyline(polyline);
    if (points.length < 2) return null;

    const width = 600;
    const height = 240;
    const pad = 24;

    const midLat =
      (bounds.southwest.lat + bounds.northeast.lat) / 2 || points[0].lat;
    const cosLat = Math.cos((midLat * Math.PI) / 180);

    const lats = points.map((p) => p.lat);
    const lngs = points.map((p) => p.lng * cosLat);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    const minLng = Math.min(...lngs);
    const maxLng = Math.max(...lngs);
    const spanLat = Math.max(maxLat - minLat, 1e-6);
    const spanLng = Math.max(maxLng - minLng, 1e-6);
    const scale = Math.min(
      (width - pad * 2) / spanLng,
      (height - pad * 2) / spanLat
    );
    const offsetX = (width - spanLng * scale) / 2;
    const offsetY = (height - spanLat * scale) / 2;

    const projected = points.map((p) => {
      const x = (p.lng * cosLat - minLng) * scale + offsetX;
      // SVG y grows downward; latitude grows upward, so flip.
      const y = height - ((p.lat - minLat) * scale + offsetY);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    });

    return {
      d: `M${projected.join(" L")}`,
      start: projected[0],
      end: projected[projected.length - 1],
      width,
      height,
    };
  }, [polyline, bounds]);

  if (!path) return null;

  const [startX, startY] = path.start.split(",");
  const [endX, endY] = path.end.split(",");

  return (
    <svg
      viewBox={`0 0 ${path.width} ${path.height}`}
      className="h-full w-full"
      preserveAspectRatio="xMidYMid meet"
    >
      <path
        d={path.d}
        fill="none"
        stroke={color}
        strokeWidth={4}
        strokeLinecap="round"
        strokeLinejoin="round"
        opacity={0.95}
      />
      <circle cx={startX} cy={startY} r={6} fill="var(--accent)" />
      <circle cx={startX} cy={startY} r={2.4} fill="white" />
      <circle cx={endX} cy={endY} r={6} fill="var(--ink-secondary)" />
    </svg>
  );
}
