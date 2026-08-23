"use client";

import { useEffect, useMemo } from "react";
import {
  CircleMarker,
  MapContainer,
  Polyline,
  TileLayer,
  useMap,
} from "react-leaflet";
import type { LatLngBoundsExpression, LatLngExpression } from "leaflet";
import { decodePolyline } from "@/lib/polyline";
import type { Bounds } from "@/lib/types";

export function InteractiveRouteMap({
  polyline,
  bounds,
  color,
}: {
  polyline: string;
  bounds: Bounds;
  color: string;
}) {
  const points = useMemo<LatLngExpression[]>(
    () => decodePolyline(polyline).map((point) => [point.lat, point.lng]),
    [polyline]
  );
  const routeBounds = useMemo<LatLngBoundsExpression>(
    () => [
      [bounds.southwest.lat, bounds.southwest.lng],
      [bounds.northeast.lat, bounds.northeast.lng],
    ],
    [bounds]
  );

  if (points.length < 2) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-ink-secondary">
        Route map unavailable
      </div>
    );
  }

  return (
    <MapContainer
      bounds={routeBounds}
      boundsOptions={{ padding: [28, 28] }}
      className="route-map h-full w-full"
      scrollWheelZoom={false}
      zoomControl
    >
      <FitRouteBounds bounds={routeBounds} />
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>'
        subdomains="abcd"
        url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
      />
      <Polyline
        positions={points}
        pathOptions={{ color: "rgba(0, 0, 0, 0.7)", weight: 8, opacity: 0.8 }}
      />
      <Polyline
        positions={points}
        pathOptions={{ color, weight: 5, opacity: 1 }}
      />
      <CircleMarker
        center={points[0]}
        radius={7}
        pathOptions={{ color: "white", weight: 2, fillColor: "rgb(5, 107, 235)", fillOpacity: 1 }}
      />
      <CircleMarker
        center={points[points.length - 1]}
        radius={7}
        pathOptions={{ color: "white", weight: 2, fillColor: "rgb(70, 70, 70)", fillOpacity: 1 }}
      />
    </MapContainer>
  );
}

function FitRouteBounds({ bounds }: { bounds: LatLngBoundsExpression }) {
  const map = useMap();

  useEffect(() => {
    map.fitBounds(bounds, { padding: [28, 28] });
  }, [bounds, map]);

  return null;
}
