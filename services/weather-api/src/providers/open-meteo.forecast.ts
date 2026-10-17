import { Injectable } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import { config } from '../config';
import { localParts, toIso } from '../common/time';
import { mapWmo } from '../domain/condition';
import { CurrentData, DailyRecord, ForecastSnapshot, HourlyRecord } from '../domain/types';
import { fetchJson, ProviderError } from './http';

export const OPEN_METEO = 'open_meteo';

const HOURLY = [
  'temperature_2m',
  'apparent_temperature',
  'relative_humidity_2m',
  'dew_point_2m',
  'precipitation_probability',
  'precipitation',
  'weather_code',
  'is_day',
  'pressure_msl',
  'surface_pressure',
  'cloud_cover',
  'visibility',
  'wind_speed_10m',
  'wind_direction_10m',
  'wind_gusts_10m',
  'uv_index',
] as const;

const CURRENT = HOURLY.filter((v) => v !== 'precipitation_probability');

const DAILY = [
  'weather_code',
  'temperature_2m_max',
  'temperature_2m_min',
  'apparent_temperature_max',
  'apparent_temperature_min',
  'sunrise',
  'sunset',
  'daylight_duration',
  'uv_index_max',
  'precipitation_sum',
  'precipitation_probability_max',
  'wind_speed_10m_max',
  'wind_gusts_10m_max',
  'wind_direction_10m_dominant',
] as const;

/** Expected unit per variable; mismatching variables are nulled and reported (never silently converted). */
const EXPECTED_UNITS: Record<string, string> = {
  temperature_2m: '°C',
  apparent_temperature: '°C',
  dew_point_2m: '°C',
  relative_humidity_2m: '%',
  precipitation_probability: '%',
  precipitation: 'mm',
  pressure_msl: 'hPa',
  surface_pressure: 'hPa',
  cloud_cover: '%',
  visibility: 'm',
  wind_speed_10m: 'm/s',
  wind_gusts_10m: 'm/s',
  wind_direction_10m: '°',
  temperature_2m_max: '°C',
  temperature_2m_min: '°C',
  apparent_temperature_max: '°C',
  apparent_temperature_min: '°C',
  precipitation_sum: 'mm',
  wind_speed_10m_max: 'm/s',
  wind_gusts_10m_max: 'm/s',
};

type Series = Record<string, (number | null)[]>;

export interface RawForecast {
  latitude: number;
  longitude: number;
  elevation?: number;
  timezone: string;
  current_units?: Record<string, string>;
  current?: Record<string, number | null> & { time: number };
  hourly_units?: Record<string, string>;
  hourly?: Series & { time: number[] };
  daily_units?: Record<string, string>;
  daily?: Series & { time: number[] };
}

export interface ForecastResult {
  snapshot: ForecastSnapshot;
  warnings: string[];
}

@Injectable()
export class OpenMeteoForecastAdapter {
  readonly providerId = config.providerMode === 'fixture' ? 'fixture' : OPEN_METEO;

  async fetch(lat: number, lon: number, timezone: string): Promise<ForecastResult> {
    const raw = await this.load(lat, lon, timezone);
    return parseForecast(raw, lat, lon, timezone);
  }

  private async load(lat: number, lon: number, timezone: string): Promise<RawForecast> {
    if (config.providerMode === 'fixture') {
      return JSON.parse(fs.readFileSync(path.join(config.fixtureDir, 'open-meteo-forecast.json'), 'utf8'));
    }
    const p = new URLSearchParams({
      latitude: lat.toFixed(4),
      longitude: lon.toFixed(4),
      current: CURRENT.join(','),
      hourly: HOURLY.join(','),
      daily: DAILY.join(','),
      past_days: '1',
      forecast_days: '10',
      timezone,
      timeformat: 'unixtime',
      wind_speed_unit: 'ms',
    });
    if (config.openMeteo.apiKey) p.set('apikey', config.openMeteo.apiKey);
    return fetchJson<RawForecast>(OPEN_METEO, `${config.openMeteo.forecastHost}/v1/forecast?${p}`);
  }
}

export function parseForecast(raw: RawForecast, lat: number, lon: number, timezone: string): ForecastResult {
  if (!raw || !raw.hourly || !Array.isArray(raw.hourly.time) || !raw.daily || !Array.isArray(raw.daily.time)) {
    throw new ProviderError(OPEN_METEO, 'MALFORMED');
  }
  const warnings: string[] = [];
  const hourly = checkSeries(raw.hourly, raw.hourly_units, warnings, 'hourly');
  const daily = checkSeries(raw.daily, raw.daily_units, warnings, 'daily');
  const fetchedAt = toIso(Date.now());

  const hourlyRecords: HourlyRecord[] = raw.hourly.time.map((t, i) => {
    const ms = t * 1000;
    const lp = localParts(ms, timezone);
    const code = num(hourly.weather_code, i);
    const isDay = num(hourly.is_day, i);
    return {
      time: toIso(ms),
      localTime: lp.localTime,
      localDate: lp.localDate,
      utcOffsetSeconds: lp.utcOffsetSeconds,
      intervalStartAt: toIso(ms - 3_600_000),
      intervalEndAt: toIso(ms),
      temperatureC: num(hourly.temperature_2m, i),
      feelsLikeC: num(hourly.apparent_temperature, i),
      humidityPct: pct(num(hourly.relative_humidity_2m, i), warnings),
      dewPointC: num(hourly.dew_point_2m, i),
      rainProbabilityPct: pct(num(hourly.precipitation_probability, i), warnings),
      precipitationMm: nonNeg(num(hourly.precipitation, i)),
      conditionCode: mapWmo(code),
      rawConditionCode: code,
      isDay: isDay === null ? null : isDay === 1,
      seaLevelPressureHpa: num(hourly.pressure_msl, i),
      surfacePressureHpa: num(hourly.surface_pressure, i),
      cloudCoverPct: pct(num(hourly.cloud_cover, i), warnings),
      visibilityM: nonNeg(num(hourly.visibility, i)),
      windSpeedMs: nonNeg(num(hourly.wind_speed_10m, i)),
      windDirectionDeg: num(hourly.wind_direction_10m, i),
      windGustMs: nonNeg(num(hourly.wind_gusts_10m, i)),
      uvIndex: nonNeg(num(hourly.uv_index, i)),
    };
  });
  assertMonotonic(hourlyRecords.map((r) => Date.parse(r.time)));

  const dailyRecords: DailyRecord[] = raw.daily.time.map((t, i) => {
    const startMs = t * 1000;
    const lp = localParts(startMs, timezone);
    const next = raw.daily!.time[i + 1];
    const code = num(daily.weather_code, i);
    const minC = num(daily.temperature_2m_min, i);
    const maxC = num(daily.temperature_2m_max, i);
    return {
      localDate: lp.localDate,
      startAt: toIso(startMs),
      endAt: toIso(next !== undefined ? next * 1000 : startMs + 86_400_000),
      conditionCode: mapWmo(code),
      rawConditionCode: code,
      minC: minC !== null && maxC !== null && minC > maxC ? null : minC,
      maxC,
      feelsMinC: num(daily.apparent_temperature_min, i),
      feelsMaxC: num(daily.apparent_temperature_max, i),
      // Polar day/night: provider returns no event (null or out-of-day value) — never 00:00.
      sunriseAt: eventInDay(num(daily.sunrise, i), startMs),
      sunsetAt: eventInDay(num(daily.sunset, i), startMs),
      daylightSeconds: num(daily.daylight_duration, i),
      uvIndexMax: nonNeg(num(daily.uv_index_max, i)),
      precipitationTotalMm: nonNeg(num(daily.precipitation_sum, i)),
      rainProbabilityMaxPct: pct(num(daily.precipitation_probability_max, i), warnings),
      windSpeedMaxMs: nonNeg(num(daily.wind_speed_10m_max, i)),
      windGustMaxMs: nonNeg(num(daily.wind_gusts_10m_max, i)),
      windDirectionDominantDeg: num(daily.wind_direction_10m_dominant, i),
    };
  });

  let current: CurrentData | null = null;
  if (raw.current && typeof raw.current.time === 'number') {
    const wrapped: Series = {};
    for (const [k, v] of Object.entries(raw.current)) if (k !== 'time' && k !== 'interval') wrapped[k] = [v as number | null];
    const c = checkSeries(wrapped, raw.current_units, warnings, 'current');
    const code = num(c.weather_code, 0);
    const isDay = num(c.is_day, 0);
    current = {
      validAt: toIso(raw.current.time * 1000),
      temperatureC: num(c.temperature_2m, 0),
      feelsLikeC: num(c.apparent_temperature, 0),
      humidityPct: pct(num(c.relative_humidity_2m, 0), warnings),
      dewPointC: num(c.dew_point_2m, 0),
      conditionCode: mapWmo(code),
      rawConditionCode: code,
      isDay: isDay === null ? null : isDay === 1,
      windSpeedMs: nonNeg(num(c.wind_speed_10m, 0)),
      windDirectionDeg: num(c.wind_direction_10m, 0),
      windGustMs: nonNeg(num(c.wind_gusts_10m, 0)),
      seaLevelPressureHpa: num(c.pressure_msl, 0),
      surfacePressureHpa: num(c.surface_pressure, 0),
      cloudCoverPct: pct(num(c.cloud_cover, 0), warnings),
      visibilityM: nonNeg(num(c.visibility, 0)),
      uvIndex: nonNeg(num(c.uv_index, 0)),
      precipitationMm: nonNeg(num(c.precipitation, 0)),
    };
  }

  return {
    warnings: [...new Set(warnings)],
    snapshot: {
      timezone,
      requestedCoordinate: { latitude: lat, longitude: lon },
      dataCoordinate: { latitude: raw.latitude, longitude: raw.longitude },
      elevationM: raw.elevation ?? null,
      current,
      hourly: hourlyRecords,
      daily: dailyRecords,
      fetchedAt,
    },
  };
}

function checkSeries(series: Series, units: Record<string, string> | undefined, warnings: string[], group: string): Series {
  const out: Series = {};
  const len = (series as { time?: unknown[] }).time?.length;
  for (const [k, v] of Object.entries(series)) {
    if (k === 'time') continue;
    if (!Array.isArray(v) || (len !== undefined && v.length !== len)) {
      warnings.push(`FIELD_MALFORMED:${group}.${k}`);
      continue;
    }
    const expected = EXPECTED_UNITS[k];
    if (expected && units && units[k] !== undefined && units[k] !== expected) {
      warnings.push(`UNIT_MISMATCH:${group}.${k}`);
      continue;
    }
    out[k] = v;
  }
  return out;
}

function num(arr: (number | null)[] | undefined, i: number): number | null {
  if (!arr) return null;
  const v = arr[i];
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function pct(v: number | null, warnings: string[]): number | null {
  if (v === null) return null;
  if (v < 0 || v > 100) {
    warnings.push('PERCENT_OUT_OF_RANGE');
    return null;
  }
  return v;
}

function nonNeg(v: number | null): number | null {
  return v === null || v < 0 ? null : v;
}

function eventInDay(epochSec: number | null, dayStartMs: number): string | null {
  if (epochSec === null || epochSec <= 0) return null;
  const ms = epochSec * 1000;
  if (ms < dayStartMs || ms >= dayStartMs + 26 * 3_600_000) return null;
  return toIso(ms);
}

function assertMonotonic(times: number[]): void {
  for (let i = 1; i < times.length; i++) {
    if (!(times[i] > times[i - 1])) throw new ProviderError(OPEN_METEO, 'MALFORMED');
  }
}
