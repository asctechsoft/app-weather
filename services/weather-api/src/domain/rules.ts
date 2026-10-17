/**
 * Pure aggregation and classification rules (SW024). Thresholds are the proposed
 * product values from the spec and are versioned so QA can pin them in fixtures.
 * None of these functions substitutes 0 for missing data.
 */
import { HourlyRecord } from './types';

export const RULES_VERSION = 'rules-2026.10-1';

type NumericField = {
  [K in keyof HourlyRecord]: HourlyRecord[K] extends number | null ? K : never;
}[keyof HourlyRecord];

export interface Extremum {
  value: number;
  time: string;
  localTime: string;
}

export interface MinMax {
  min: Extremum | null;
  max: Extremum | null;
  /** Number of records with a value / total records considered. */
  validCount: number;
  totalCount: number;
  complete: boolean;
}

export function minMax(records: HourlyRecord[], field: NumericField): MinMax {
  let min: Extremum | null = null;
  let max: Extremum | null = null;
  let validCount = 0;
  for (const r of records) {
    const v = r[field] as number | null;
    if (v === null || v === undefined || Number.isNaN(v)) continue;
    validCount++;
    if (!min || v < min.value) min = { value: v, time: r.time, localTime: r.localTime };
    if (!max || v > max.value) max = { value: v, time: r.time, localTime: r.localTime };
  }
  return {
    min,
    max,
    validCount,
    totalCount: records.length,
    complete: records.length > 0 && validCount === records.length,
  };
}

export interface PrecipTotal {
  totalMm: number | null;
  hoursCounted: number;
  hoursMissing: number;
  incomplete: boolean;
}

/**
 * Sums hourly precipitation whose interval lies fully inside [fromMs, toMs].
 * Each hourly amount covers its own preceding hour, so nothing is double counted.
 */
export function sumPrecipitation(records: HourlyRecord[], fromMs: number, toMs: number): PrecipTotal {
  let total = 0;
  let counted = 0;
  let missing = 0;
  for (const r of records) {
    const s = Date.parse(r.intervalStartAt);
    const e = Date.parse(r.intervalEndAt);
    if (s < fromMs || e > toMs) continue;
    if (r.precipitationMm === null) {
      missing++;
      continue;
    }
    total += r.precipitationMm;
    counted++;
  }
  const expectedHours = Math.round((toMs - fromMs) / 3_600_000);
  const gap = Math.max(0, expectedHours - counted - missing);
  return {
    // An empty window (e.g. 00:00–00:00) sums to a true 0; a window with no valid data is null.
    totalMm: expectedHours <= 0 ? 0 : counted === 0 ? null : round(total, 2),
    hoursCounted: counted,
    hoursMissing: missing + gap,
    incomplete: missing + gap > 0,
  };
}

/** Circular mean of directions in degrees (350° and 10° → 0°, never 180°). */
export function circularMeanDeg(values: (number | null)[]): number | null {
  let x = 0;
  let y = 0;
  let n = 0;
  for (const v of values) {
    if (v === null) continue;
    const rad = (v * Math.PI) / 180;
    x += Math.cos(rad);
    y += Math.sin(rad);
    n++;
  }
  if (n === 0 || (Math.abs(x) < 1e-9 && Math.abs(y) < 1e-9)) return null;
  const deg = (Math.atan2(y, x) * 180) / Math.PI;
  return normalizeDeg(deg);
}

export function normalizeDeg(deg: number): number {
  const d = ((deg % 360) + 360) % 360;
  return round(d, 1) === 360 ? 0 : round(d, 1);
}

const COMPASS_16 = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];

/** Direction the wind blows FROM, as a 16-point compass label. Calm or missing → null. */
export function compassLabel(deg: number | null, speedMs: number | null): string | null {
  if (deg === null) return null;
  if (speedMs !== null && speedMs < 0.5) return null;
  return COMPASS_16[Math.round(normalizeDeg(deg) / 22.5) % 16];
}

/** WMO Beaufort scale upper bounds in m/s (10 m wind). */
export const BEAUFORT_TABLE_VERSION = 'wmo-beaufort-1';
const BEAUFORT_UPPER = [0.5, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7];

export function beaufort(speedMs: number | null): number | null {
  if (speedMs === null || speedMs < 0) return null;
  const idx = BEAUFORT_UPPER.findIndex((u) => speedMs < u);
  return idx === -1 ? 12 : idx;
}

export type UvCategory = 'low' | 'moderate' | 'high' | 'very_high' | 'extreme';

/** EPA UV scale; classified on the unrounded value. */
export function uvCategory(uv: number | null): UvCategory | null {
  if (uv === null || uv < 0) return null;
  if (uv < 3) return 'low';
  if (uv < 6) return 'moderate';
  if (uv < 8) return 'high';
  if (uv < 11) return 'very_high';
  return 'extreme';
}

export interface TimeWindow {
  from: string;
  to: string;
  fromLocal: string;
  toLocal: string;
  peak: Extremum;
}

/**
 * Contiguous hours with value >= threshold. If several windows exist, return the one
 * containing the overall maximum. Returns null when no hour reaches the threshold.
 */
export function windowAbove(records: HourlyRecord[], field: NumericField, threshold: number): TimeWindow | null {
  const windows: HourlyRecord[][] = [];
  let cur: HourlyRecord[] = [];
  for (const r of records) {
    const v = r[field] as number | null;
    if (v !== null && v >= threshold) cur.push(r);
    else if (cur.length) {
      windows.push(cur);
      cur = [];
    }
  }
  if (cur.length) windows.push(cur);
  if (!windows.length) return null;
  let best: { w: HourlyRecord[]; peak: Extremum } | null = null;
  for (const w of windows) {
    const mm = minMax(w, field).max!;
    if (!best || mm.value > best.peak.value) best = { w, peak: mm };
  }
  const first = best!.w[0];
  const last = best!.w[best!.w.length - 1];
  const endMs = Date.parse(last.time) + 3_600_000;
  return {
    from: first.time,
    to: new Date(endMs).toISOString().replace('.000Z', 'Z'),
    fromLocal: first.localTime,
    toLocal: addHourLocal(last.localTime),
    peak: best!.peak,
  };
}

function addHourLocal(localTime: string): string {
  const [d, t] = localTime.split('T');
  const h = Number(t.slice(0, 2)) + 1;
  return h >= 24 ? `${d}T24:00` : `${d}T${String(h).padStart(2, '0')}:00`;
}

export type AqiCategory =
  | 'good'
  | 'moderate'
  | 'unhealthy_sensitive'
  | 'unhealthy'
  | 'very_unhealthy'
  | 'hazardous';

/** US AQI categories (AirNow). Never mixed with European AQI. */
export function usAqiCategory(aqi: number | null): AqiCategory | null {
  if (aqi === null || aqi < 0) return null;
  const v = Math.round(aqi);
  if (v <= 50) return 'good';
  if (v <= 100) return 'moderate';
  if (v <= 150) return 'unhealthy_sensitive';
  if (v <= 200) return 'unhealthy';
  if (v <= 300) return 'very_unhealthy';
  return 'hazardous';
}

export type HumidityLabel = 'low' | 'moderate' | 'high' | 'very_high';

export function humidityLabel(pct: number | null): HumidityLabel | null {
  if (pct === null || pct < 0 || pct > 100) return null;
  if (pct < 30) return 'low';
  if (pct < 60) return 'moderate';
  if (pct <= 80) return 'high';
  return 'very_high';
}

export type VisibilityCategory = 'very_poor' | 'poor' | 'moderate' | 'good';

export function visibilityCategory(m: number | null): VisibilityCategory | null {
  if (m === null || m < 0) return null;
  if (m < 1000) return 'very_poor';
  if (m < 5000) return 'poor';
  if (m < 10000) return 'moderate';
  return 'good';
}

export type FeelsLabel = 'warmer' | 'cooler' | 'similar';

/** Uses the unrounded delta; |delta| < 0.5 °C is "similar". */
export function feelsLabel(actualC: number | null, feelsC: number | null): { deltaC: number; label: FeelsLabel } | null {
  if (actualC === null || feelsC === null) return null;
  const delta = feelsC - actualC;
  const label: FeelsLabel = Math.abs(delta) < 0.5 ? 'similar' : delta > 0 ? 'warmer' : 'cooler';
  return { deltaC: round(delta, 2), label };
}

export type PressureTrend = 'rising' | 'falling' | 'steady';

export interface PressureTrendResult {
  deltaHpa: number;
  hours: 3;
  trend: PressureTrend;
  rate: 'slow' | 'fast' | null;
  from: string;
  to: string;
}

/** p(t) − p(t−3h) using exactly two valid hourly points of the same series. */
export function pressureTrend(records: HourlyRecord[], atMs: number): PressureTrendResult | null {
  const hourMs = Math.floor(atMs / 3_600_000) * 3_600_000;
  const byTime = new Map(records.map((r) => [Date.parse(r.time), r]));
  const now = byTime.get(hourMs);
  const past = byTime.get(hourMs - 3 * 3_600_000);
  if (!now || !past || now.seaLevelPressureHpa === null || past.seaLevelPressureHpa === null) return null;
  const delta = now.seaLevelPressureHpa - past.seaLevelPressureHpa;
  const trend: PressureTrend = Math.abs(delta) < 1 ? 'steady' : delta > 0 ? 'rising' : 'falling';
  return {
    deltaHpa: round(delta, 1),
    hours: 3,
    trend,
    rate: trend === 'steady' ? null : Math.abs(delta) >= 3 ? 'fast' : 'slow',
    from: past.time,
    to: now.time,
  };
}

/** First hour within the horizon meeting the next-shower rule (≥0.2 mm and PoP ≥ 50% if PoP exists). */
export function nextShower(
  records: HourlyRecord[],
  fromMs: number,
  horizonHours = 48,
): { time: string; localTime: string; precipitationMm: number; rainProbabilityPct: number | null; basis: 'amount_and_probability' | 'amount_only' } | null {
  const toMs = fromMs + horizonHours * 3_600_000;
  for (const r of records) {
    const t = Date.parse(r.time);
    if (t < fromMs - 3_600_000 || t > toMs) continue;
    if (r.precipitationMm === null || r.precipitationMm < 0.2) continue;
    if (r.rainProbabilityPct !== null && r.rainProbabilityPct < 50) continue;
    return {
      time: r.time,
      localTime: r.localTime,
      precipitationMm: r.precipitationMm,
      rainProbabilityPct: r.rainProbabilityPct,
      basis: r.rainProbabilityPct === null ? 'amount_only' : 'amount_and_probability',
    };
  }
  return null;
}

export function median(values: (number | null)[]): number | null {
  const v = values.filter((x): x is number => x !== null).sort((a, b) => a - b);
  if (!v.length) return null;
  const mid = Math.floor(v.length / 2);
  return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

export function round(v: number, digits: number): number {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
}
