import * as SunCalc from 'suncalc';
import { localParts, toIso } from '../common/time';

/**
 * Computed astronomy (fixed algorithm: suncalc 1.9.0, based on Astronomical Algorithms).
 * Events are searched inside the location's local day [startMs, endMs); a missing event
 * (polar day/night, no moonrise that day) is returned as null with a status — never 00:00.
 */
export const ASTRONOMY_ALGORITHM = 'suncalc-1.9.0';

export type EventStatus = 'occurs' | 'always_up' | 'always_down' | 'no_event';

export interface SunEvents {
  solarNoonAt: string | null;
  civilDawnAt: string | null;
  civilDuskAt: string | null;
  sunriseAt: string | null;
  sunsetAt: string | null;
  status: EventStatus;
}

export interface MoonInfo {
  moonriseAt: string | null;
  moonsetAt: string | null;
  riseSetStatus: EventStatus;
  illuminationPct: number;
  phase: number;
  phaseName: 'new_moon' | 'waxing_crescent' | 'first_quarter' | 'waxing_gibbous' | 'full_moon' | 'waning_gibbous' | 'last_quarter' | 'waning_crescent';
  validAt: string;
}

export interface UpcomingPhase {
  phase: 'new_moon' | 'first_quarter' | 'full_moon' | 'last_quarter';
  at: string;
  localDate: string;
}

const RAD = Math.PI / 180;
const MIN = 60_000;

function findCrossings(startMs: number, endMs: number, f: (ms: number) => number): { rise: number | null; set: number | null; alwaysUp: boolean } {
  const step = 10 * MIN;
  let rise: number | null = null;
  let set: number | null = null;
  let prevT = startMs;
  let prev = f(prevT);
  let anyBelow = prev < 0;
  for (let t = startMs + step; t <= endMs; t += step) {
    const cur = f(t);
    if (cur < 0) anyBelow = true;
    if (prev < 0 !== cur < 0) {
      // bisection to ~30 s
      let a = prevT;
      let b = t;
      for (let i = 0; i < 6; i++) {
        const m = (a + b) / 2;
        if (f(m) < 0 === prev < 0) a = m;
        else b = m;
      }
      const at = Math.round((a + b) / 2 / MIN) * MIN;
      if (prev < 0 && rise === null) rise = at;
      if (prev >= 0 && set === null) set = at;
    }
    prevT = t;
    prev = cur;
  }
  return { rise, set, alwaysUp: !anyBelow };
}

function iso(ms: number | null): string | null {
  return ms === null ? null : toIso(ms);
}

export function sunEvents(lat: number, lon: number, dayStartMs: number, dayEndMs: number): SunEvents {
  const alt = (h0: number) => (ms: number) => SunCalc.getPosition(new Date(ms), lat, lon).altitude - h0 * RAD;
  const horizon = findCrossings(dayStartMs, dayEndMs, alt(-0.833));
  const civil = findCrossings(dayStartMs, dayEndMs, alt(-6));
  // Solar noon = maximum altitude within the local day (sampled + refined).
  let best = dayStartMs;
  let bestAlt = -Infinity;
  for (let t = dayStartMs; t < dayEndMs; t += 10 * MIN) {
    const a = SunCalc.getPosition(new Date(t), lat, lon).altitude;
    if (a > bestAlt) {
      bestAlt = a;
      best = t;
    }
  }
  for (let t = best - 10 * MIN; t <= best + 10 * MIN; t += MIN) {
    const a = SunCalc.getPosition(new Date(t), lat, lon).altitude;
    if (a > bestAlt) {
      bestAlt = a;
      best = t;
    }
  }
  const status: EventStatus =
    horizon.rise !== null || horizon.set !== null ? 'occurs' : horizon.alwaysUp ? 'always_up' : 'always_down';
  return {
    solarNoonAt: toIso(Math.round(best / MIN) * MIN),
    civilDawnAt: iso(civil.rise),
    civilDuskAt: iso(civil.set),
    sunriseAt: iso(horizon.rise),
    sunsetAt: iso(horizon.set),
    status,
  };
}

export function moonInfo(lat: number, lon: number, dayStartMs: number, dayEndMs: number, atMs: number): MoonInfo {
  const f = (ms: number) => SunCalc.getMoonPosition(new Date(ms), lat, lon).altitude - 0.133 * RAD;
  const c = findCrossings(dayStartMs, dayEndMs, f);
  const ill = SunCalc.getMoonIllumination(new Date(atMs));
  const status: EventStatus = c.rise !== null || c.set !== null ? 'occurs' : c.alwaysUp ? 'always_up' : 'always_down';
  return {
    moonriseAt: iso(c.rise),
    moonsetAt: iso(c.set),
    riseSetStatus: status,
    illuminationPct: Math.round(ill.fraction * 1000) / 10,
    phase: Math.round(ill.phase * 1000) / 1000,
    phaseName: phaseName(ill.phase),
    validAt: toIso(atMs),
  };
}

function phaseName(p: number): MoonInfo['phaseName'] {
  if (p < 0.02 || p >= 0.98) return 'new_moon';
  if (p < 0.23) return 'waxing_crescent';
  if (p < 0.27) return 'first_quarter';
  if (p < 0.48) return 'waxing_gibbous';
  if (p < 0.52) return 'full_moon';
  if (p < 0.73) return 'waning_gibbous';
  if (p < 0.77) return 'last_quarter';
  return 'waning_crescent';
}

/** Principal phases strictly after `fromMs`, in time order. */
export function upcomingPhases(fromMs: number, tz: string, count = 4): UpcomingPhase[] {
  const targets: [number, UpcomingPhase['phase']][] = [
    [0, 'new_moon'],
    [0.25, 'first_quarter'],
    [0.5, 'full_moon'],
    [0.75, 'last_quarter'],
  ];
  const phaseAt = (ms: number) => SunCalc.getMoonIllumination(new Date(ms)).phase;
  // signed distance from target in (-0.5, 0.5]
  const dist = (p: number, target: number) => {
    let d = p - target;
    if (d > 0.5) d -= 1;
    if (d <= -0.5) d += 1;
    return d;
  };
  const out: UpcomingPhase[] = [];
  const step = 3 * 3_600_000;
  let prevT = fromMs;
  let prevP = phaseAt(prevT);
  for (let t = fromMs + step; t < fromMs + 40 * 86_400_000 && out.length < count; t += step) {
    const p = phaseAt(t);
    for (const [target, name] of targets) {
      const d0 = dist(prevP, target);
      const d1 = dist(p, target);
      if (d0 < 0 && d1 >= 0 && Math.abs(d1 - d0) < 0.25) {
        let a = prevT;
        let b = t;
        for (let i = 0; i < 12; i++) {
          const m = (a + b) / 2;
          if (dist(phaseAt(m), target) < 0) a = m;
          else b = m;
        }
        const at = Math.round((a + b) / 2 / MIN) * MIN;
        if (at > fromMs) out.push({ phase: name, at: toIso(at), localDate: localParts(at, tz).localDate });
      }
    }
    prevT = t;
    prevP = p;
  }
  return out.slice(0, count);
}
