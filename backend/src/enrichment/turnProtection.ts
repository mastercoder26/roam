import type { LatLng } from "../types.js";
import { neutralTurns, type TurnExposure } from "./types.js";

const SIGNAL_MATCH_RADIUS_M = 25;

export interface TrafficSignalNode {
  lat: number;
  lon: number;
  tags?: Record<string, string>;
}

function metersBetween(a: LatLng, b: { lat: number; lng: number }): number {
  const latRad = ((a.lat + b.lat) / 2) * (Math.PI / 180);
  const dLat = (b.lat - a.lat) * 111_320;
  const dLng = (b.lng - a.lng) * 111_320 * Math.cos(latRad);
  return Math.sqrt(dLat * dLat + dLng * dLng);
}

/**
 * Turn protection is available only when every left turn has exactly one nearby
 * traffic-signal match. Stop controls and uncertain matches do not establish
 * protection from oncoming traffic.
 */
export function determineTurnProtection(
  turnPoints: LatLng[],
  signalNodes: TrafficSignalNode[]
): TurnExposure {
  if (turnPoints.length === 0) {
    return { ...neutralTurns(), available: true };
  }

  const hasUnambiguousSignalAtEveryTurn = turnPoints.every((turnPoint) =>
    signalNodes.filter((node) =>
      node.tags?.highway === "traffic_signals" &&
      metersBetween(turnPoint, { lat: node.lat, lng: node.lon }) <= SIGNAL_MATCH_RADIUS_M
    ).length === 1
  );

  if (!hasUnambiguousSignalAtEveryTurn) {
    return neutralTurns();
  }

  return {
    available: true,
    unprotectedLeftTurns: 0,
    protectedLeftTurns: turnPoints.length,
    unprotectedTurnShare: 0,
  };
}
