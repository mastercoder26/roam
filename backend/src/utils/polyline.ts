import type { LatLng } from "../types.js";

/** Decode a Google encoded polyline into lat/lng points. */
export function decodePolyline(encoded: string): LatLng[] {
  const points: LatLng[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte: number;

    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    lat += result & 1 ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;

    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    lng += result & 1 ? ~(result >> 1) : result >> 1;

    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }

  return points;
}

function haversineMeters(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Sample evenly spaced points along a polyline (default ~80 points). */
export function samplePolylinePoints(
  encoded: string,
  targetCount = 80
): LatLng[] {
  const decoded = decodePolyline(encoded);
  if (decoded.length === 0) return [];
  if (decoded.length === 1) return decoded;
  if (decoded.length <= targetCount) return decoded;

  const cumulative: number[] = [0];
  for (let i = 1; i < decoded.length; i++) {
    cumulative.push(cumulative[i - 1] + haversineMeters(decoded[i - 1], decoded[i]));
  }

  const total = cumulative[cumulative.length - 1];
  if (total === 0) return [decoded[0]];

  const samples: LatLng[] = [];
  const step = total / (targetCount - 1);

  for (let s = 0; s < targetCount; s++) {
    const target = s === targetCount - 1 ? total : s * step;
    let seg = 0;
    while (seg < cumulative.length - 1 && cumulative[seg + 1] < target) {
      seg++;
    }

    const segStart = cumulative[seg];
    const segEnd = cumulative[seg + 1];
    const t =
      segEnd === segStart ? 0 : (target - segStart) / (segEnd - segStart);

    const a = decoded[seg];
    const b = decoded[Math.min(seg + 1, decoded.length - 1)];
    samples.push({
      lat: a.lat + t * (b.lat - a.lat),
      lng: a.lng + t * (b.lng - a.lng),
    });
  }

  return samples;
}

/** Parse protobuf duration strings like "5309s" into seconds. */
export function parseDurationSeconds(value: string | undefined | null): number {
  if (!value) return 0;
  const match = value.match(/^(\d+(?:\.\d+)?)s$/);
  if (!match) return 0;
  return Math.round(parseFloat(match[1]));
}

