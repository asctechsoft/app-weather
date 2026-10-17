import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';
import { selectAlternates } from '../src/catalog/geonames.importer';
import { TtlCache } from '../src/common/cache';
import { mapWmo } from '../src/domain/condition';
import { parseAirQuality } from '../src/providers/open-meteo.air-quality';
import { parseForecast, RawForecast } from '../src/providers/open-meteo.forecast';
import { parseKp } from '../src/providers/noaa';
import { redactUrl } from '../src/providers/http';
import { moonInfo, sunEvents, upcomingPhases } from '../src/providers/astronomy';
import { localDayStartMs } from '../src/common/time';
import { fold } from '../src/providers/open-meteo.geocoding';
import { uuidV5 } from '../src/locations/location.repository';

const FIX = path.resolve(__dirname, '../../../packages/contracts/fixtures');
const load = (f: string) => JSON.parse(fs.readFileSync(path.join(FIX, f), 'utf8'));

describe('Open-Meteo forecast adapter', () => {
  const raw: RawForecast = load('open-meteo-forecast.json');

  it('parses the recorded fixture into canonical records', () => {
    const { snapshot, warnings } = parseForecast(raw, 21.0245, 105.8412, 'Asia/Bangkok');
    expect(warnings).toEqual([]);
    expect(snapshot.hourly.length).toBe(raw.hourly!.time.length);
    expect(snapshot.daily.length).toBe(raw.daily!.time.length);
    for (const d of snapshot.daily) if (d.minC !== null && d.maxC !== null) expect(d.minC).toBeLessThanOrEqual(d.maxC);
    expect(snapshot.hourly[0].time.endsWith('Z')).toBe(true);
    expect(snapshot.current).not.toBeNull();
    // Daily local dates are unique and consecutive.
    const dates = snapshot.daily.map((d) => d.localDate);
    expect(new Set(dates).size).toBe(dates.length);
  });

  it('nulls a variable whose unit does not match instead of converting silently', () => {
    const bad = structuredClone(raw);
    bad.hourly_units!.wind_speed_10m = 'km/h';
    const { snapshot, warnings } = parseForecast(bad, 0, 0, 'UTC');
    expect(warnings).toContain('UNIT_MISMATCH:hourly.wind_speed_10m');
    expect(snapshot.hourly.every((h) => h.windSpeedMs === null)).toBe(true);
    expect(snapshot.hourly.some((h) => h.temperatureC !== null)).toBe(true);
  });

  it('keeps missing values as null (never 0)', () => {
    const bad = structuredClone(raw);
    bad.hourly!.precipitation = bad.hourly!.precipitation.map(() => null);
    const { snapshot } = parseForecast(bad, 0, 0, 'UTC');
    expect(snapshot.hourly.every((h) => h.precipitationMm === null)).toBe(true);
  });

  it('flags arrays whose length differs from time', () => {
    const bad = structuredClone(raw);
    bad.hourly!.uv_index = bad.hourly!.uv_index.slice(1);
    const { warnings, snapshot } = parseForecast(bad, 0, 0, 'UTC');
    expect(warnings).toContain('FIELD_MALFORMED:hourly.uv_index');
    expect(snapshot.hourly.every((h) => h.uvIndex === null)).toBe(true);
  });

  it('rejects malformed payloads', () => {
    expect(() => parseForecast({} as RawForecast, 0, 0, 'UTC')).toThrow();
  });

  it('maps unknown WMO codes to UNKNOWN, never to clear', () => {
    expect(mapWmo(42)).toBe('UNKNOWN');
    expect(mapWmo(null)).toBe('UNKNOWN');
    expect(mapWmo(66)).toBe('FREEZING_RAIN');
    expect(mapWmo(81)).toBe('SHOWERS');
  });
});

describe('other adapters', () => {
  it('parses air quality with station-less model data', () => {
    const aq = parseAirQuality(load('open-meteo-air-quality.json'), 'Asia/Bangkok');
    expect(aq.hourly.length).toBeGreaterThan(0);
    expect(aq.current?.usAqi === null || typeof aq.current?.usAqi === 'number').toBe(true);
  });

  it('parses NOAA Kp in both object and array formats', () => {
    expect(parseKp(load('noaa-kp-forecast.json')).length).toBeGreaterThan(0);
    const arr = parseKp([
      ['time_tag', 'kp', 'observed', 'noaa_scale'],
      ['2026-10-15 00:00:00', '2.33', 'observed', null],
    ]);
    expect(arr[0]).toMatchObject({ time: '2026-10-15T00:00:00Z', kp: 2.33, kind: 'observed' });
    expect(() => parseKp({})).toThrow();
  });

  it('redacts provider keys from URLs', () => {
    expect(redactUrl('https://x/y?latitude=1&apikey=SECRET&key=K2')).toBe('https://x/y?latitude=1&apikey=***&key=***');
  });

  it('folds diacritics for search', () => {
    expect(fold('Hà Nội')).toBe('ha noi');
    expect(fold('Đà Nẵng')).toBe('da nang');
  });

  it('location IDs are stable UUIDv5', () => {
    expect(uuidV5('geonames:1581130')).toBe(uuidV5('geonames:1581130'));
    expect(uuidV5('geonames:1581130')).not.toBe(uuidV5('geonames:2643743'));
    expect(uuidV5('geonames:1581130')).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});

describe('astronomy', () => {
  it('reports polar night instead of 00:00 in Tromsø in December', () => {
    const tz = 'Europe/Oslo';
    const s = localDayStartMs('2026-12-21', tz);
    const e = localDayStartMs('2026-12-22', tz);
    const sun = sunEvents(69.6492, 18.9553, s, e);
    expect(sun.sunriseAt).toBeNull();
    expect(sun.sunsetAt).toBeNull();
    expect(sun.status).toBe('always_down');
  });

  it('computes Hanoi sun events inside the local day', () => {
    const tz = 'Asia/Bangkok';
    const s = localDayStartMs('2026-10-15', tz);
    const e = localDayStartMs('2026-10-16', tz);
    const sun = sunEvents(21.0245, 105.8412, s, e);
    expect(sun.status).toBe('occurs');
    const rise = Date.parse(sun.sunriseAt!);
    const noon = Date.parse(sun.solarNoonAt!);
    const set = Date.parse(sun.sunsetAt!);
    expect(rise).toBeGreaterThan(s);
    expect(rise).toBeLessThan(noon);
    expect(noon).toBeLessThan(set);
    expect(Date.parse(sun.civilDawnAt!)).toBeLessThan(rise);
    const m = moonInfo(21.0245, 105.8412, s, e, s + 12 * 3_600_000);
    expect(m.illuminationPct).toBeGreaterThanOrEqual(0);
    expect(m.illuminationPct).toBeLessThanOrEqual(100);
  });

  it('upcoming phases are strictly after now and ordered', () => {
    const from = Date.UTC(2026, 9, 15);
    const p = upcomingPhases(from, 'UTC', 4);
    expect(p.length).toBe(4);
    for (let i = 0; i < p.length; i++) {
      expect(Date.parse(p[i].at)).toBeGreaterThan(from);
      if (i) expect(Date.parse(p[i].at)).toBeGreaterThan(Date.parse(p[i - 1].at));
    }
  });
});

describe('cache', () => {
  it('collapses concurrent misses into one upstream call (single-flight)', async () => {
    const cache = new TtlCache();
    let calls = 0;
    const load = () => new Promise<number>((r) => setTimeout(() => r(++calls), 10));
    const results = await Promise.all(Array.from({ length: 100 }, () => cache.getOrLoad('k', 1000, 5000, load)));
    expect(calls).toBe(1);
    expect(results.every((r) => r.value === 1)).toBe(true);
  });

  it('serves stale only within the stale cap when upstream fails', async () => {
    let now = 0;
    const cache = new TtlCache(() => now);
    await cache.getOrLoad('k', 100, 1000, async () => 'v1');
    now = 500;
    const r = await cache.getOrLoad('k', 100, 1000, async () => {
      throw new Error('down');
    });
    expect(r).toMatchObject({ value: 'v1', stale: true });
    now = 2000;
    await expect(
      cache.getOrLoad('k', 100, 1000, async () => {
        throw new Error('down');
      }),
    ).rejects.toThrow('down');
  });
});

describe('GeoNames alias selection', () => {
  it('keeps a late Latin alias (Sài Gòn) after folding duplicates, and bounds native scripts', () => {
    const noise = Array.from({ length: 300 }, (_, i) => (i % 2 ? 'Ho Chi Minh City' : 'Thành phố Hồ Chí Minh'));
    const scripts = Array.from({ length: 30 }, (_, i) => `胡志明市${'市'.repeat(i)}`);
    const raw = [...noise, ...scripts, 'SGN', 'https://x', '700000', 'Sài Gòn', 'Saigon'].join(',');
    const out = selectAlternates('Ho Chi Minh City', 'Ho Chi Minh City', raw);
    expect(out).toContain('Sài Gòn');
    expect(out).toContain('Saigon');
    expect(out).not.toContain('https://x');
    expect(out).not.toContain('700000');
    expect(out).not.toContain('SGN');
    expect(out.filter((a) => /[一-鿿]/.test(a)).length).toBe(10);
  });
});
