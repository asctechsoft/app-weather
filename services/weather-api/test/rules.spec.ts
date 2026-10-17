import { describe, expect, it } from 'vitest';
import { localDayStartMs, localParts, addDays } from '../src/common/time';
import {
  beaufort,
  circularMeanDeg,
  compassLabel,
  feelsLabel,
  humidityLabel,
  minMax,
  nextShower,
  pressureTrend,
  sumPrecipitation,
  usAqiCategory,
  uvCategory,
  visibilityCategory,
  windowAbove,
} from '../src/domain/rules';
import { HourlyRecord } from '../src/domain/types';

const H = 3_600_000;
const T0 = Date.UTC(2026, 9, 15, 0); // 2026-10-15T00:00Z

function hour(i: number, over: Partial<HourlyRecord> = {}): HourlyRecord {
  const ms = T0 + i * H;
  const iso = (x: number) => new Date(x).toISOString().replace('.000Z', 'Z');
  return {
    time: iso(ms),
    localTime: iso(ms).slice(0, 16),
    localDate: iso(ms).slice(0, 10),
    utcOffsetSeconds: 0,
    intervalStartAt: iso(ms - H),
    intervalEndAt: iso(ms),
    temperatureC: null,
    feelsLikeC: null,
    humidityPct: null,
    dewPointC: null,
    rainProbabilityPct: null,
    precipitationMm: null,
    conditionCode: 'UNKNOWN',
    rawConditionCode: null,
    isDay: null,
    seaLevelPressureHpa: null,
    surfacePressureHpa: null,
    cloudCoverPct: null,
    visibilityM: null,
    windSpeedMs: null,
    windDirectionDeg: null,
    windGustMs: null,
    uvIndex: null,
    ...over,
  };
}

describe('wind direction', () => {
  it('averages 350° and 10° to north, not south', () => {
    expect(circularMeanDeg([350, 10])).toBe(0);
  });
  it('maps 0° and 360° to N', () => {
    expect(compassLabel(0, 3)).toBe('N');
    expect(compassLabel(360, 3)).toBe('N');
    expect(compassLabel(45, 3)).toBe('NE');
  });
  it('returns no direction for calm or missing', () => {
    expect(compassLabel(45, 0.2)).toBeNull();
    expect(compassLabel(null, 5)).toBeNull();
  });
  it('classifies Beaufort on WMO bounds', () => {
    expect(beaufort(0.2)).toBe(0);
    expect(beaufort(3.06)).toBe(2);
    expect(beaufort(3.4)).toBe(3);
    expect(beaufort(40)).toBe(12);
    expect(beaufort(null)).toBeNull();
  });
});

describe('categories', () => {
  it('UV uses unrounded values (5.9 is moderate, 6 is high)', () => {
    expect(uvCategory(5.9)).toBe('moderate');
    expect(uvCategory(6)).toBe('high');
    expect(uvCategory(0)).toBe('low');
    expect(uvCategory(11)).toBe('extreme');
    expect(uvCategory(null)).toBeNull();
  });
  it('US AQI 184 is Unhealthy; null has no category', () => {
    expect(usAqiCategory(184)).toBe('unhealthy');
    expect(usAqiCategory(50)).toBe('good');
    expect(usAqiCategory(151)).toBe('unhealthy');
    expect(usAqiCategory(301)).toBe('hazardous');
    expect(usAqiCategory(null)).toBeNull();
  });
  it('humidity and visibility labels', () => {
    expect(humidityLabel(68)).toBe('high');
    expect(humidityLabel(101)).toBeNull();
    expect(visibilityCategory(10000)).toBe('good');
    expect(visibilityCategory(9999)).toBe('moderate');
    expect(visibilityCategory(null)).toBeNull();
  });
  it('feels-like label uses unrounded delta', () => {
    expect(feelsLabel(26.2, 26.6)!.label).toBe('similar');
    expect(feelsLabel(26.2, 28.1)!.label).toBe('warmer');
    expect(feelsLabel(26, 24)!.label).toBe('cooler');
    expect(feelsLabel(26, null)).toBeNull();
  });
});

describe('aggregation', () => {
  it('min/max ignores nulls and reports completeness', () => {
    const r = [hour(0, { temperatureC: 20 }), hour(1, { temperatureC: null }), hour(2, { temperatureC: 25 })];
    const mm = minMax(r, 'temperatureC');
    expect(mm.min!.value).toBe(20);
    expect(mm.max!.value).toBe(25);
    expect(mm.complete).toBe(false);
  });
  it('precipitation sum marks missing hours as incomplete and never turns null into 0', () => {
    const r = [hour(1, { precipitationMm: 0.4 }), hour(2, { precipitationMm: null }), hour(3, { precipitationMm: 1 })];
    const s = sumPrecipitation(r, T0, T0 + 3 * H);
    expect(s.totalMm).toBe(1.4);
    expect(s.incomplete).toBe(true);
    const none = sumPrecipitation([hour(1)], T0, T0 + H);
    expect(none.totalMm).toBeNull();
  });
  it('a forecast of 0 mm stays 0, different from null', () => {
    const s = sumPrecipitation([hour(1, { precipitationMm: 0 })], T0, T0 + H);
    expect(s.totalMm).toBe(0);
    expect(s.incomplete).toBe(false);
  });
  it('UV strong window picks the window containing the peak', () => {
    const uv = [2, 6, 7, 3, 6, 9, 8, 2];
    const r = uv.map((v, i) => hour(i, { uvIndex: v }));
    const w = windowAbove(r, 'uvIndex', 6)!;
    expect(w.peak.value).toBe(9);
    expect(w.from).toBe(r[4].time);
    expect(Date.parse(w.to)).toBe(Date.parse(r[6].time) + H);
  });
  it('pressure trend needs exactly t and t-3h', () => {
    const r = [hour(0, { seaLevelPressureHpa: 1011 }), hour(3, { seaLevelPressureHpa: 1008 })];
    const t = pressureTrend(r, T0 + 3 * H + 20 * 60_000)!;
    expect(t.deltaHpa).toBe(-3);
    expect(t.trend).toBe('falling');
    expect(pressureTrend([hour(3, { seaLevelPressureHpa: 1008 })], T0 + 3 * H)).toBeNull();
    expect(pressureTrend([hour(0, { seaLevelPressureHpa: 1008 }), hour(3, { seaLevelPressureHpa: 1008.5 })], T0 + 3 * H)!.trend).toBe('steady');
  });
  it('next shower requires amount and probability when PoP exists', () => {
    const r = [hour(1, { precipitationMm: 0.5, rainProbabilityPct: 30 }), hour(2, { precipitationMm: 0.3, rainProbabilityPct: 60 })];
    expect(nextShower(r, T0)!.time).toBe(r[1].time);
    expect(nextShower([hour(1, { precipitationMm: 0.1, rainProbabilityPct: 90 })], T0)).toBeNull();
    expect(nextShower([hour(1, { precipitationMm: 0.4 })], T0)!.basis).toBe('amount_only');
  });
});

describe('timezone and DST', () => {
  it('London 2026-10-25 is a 25-hour local day', () => {
    const tz = 'Europe/London';
    const start = localDayStartMs('2026-10-25', tz);
    const end = localDayStartMs(addDays('2026-10-25', 1), tz);
    expect((end - start) / H).toBe(25);
    expect(localParts(start, tz).localTime).toBe('2026-10-25T00:00');
  });
  it('New York 2027-03-14 is a 23-hour local day', () => {
    const tz = 'America/New_York';
    const start = localDayStartMs('2027-03-14', tz);
    const end = localDayStartMs('2027-03-15', tz);
    expect((end - start) / H).toBe(23);
  });
  it('two instants with the same London wall clock keep distinct offsets', () => {
    const a = localParts(Date.UTC(2026, 9, 25, 0, 30), 'Europe/London');
    const b = localParts(Date.UTC(2026, 9, 25, 1, 30), 'Europe/London');
    expect(a.localTime).toBe(b.localTime);
    expect(a.utcOffsetSeconds).not.toBe(b.utcOffsetSeconds);
  });
});
