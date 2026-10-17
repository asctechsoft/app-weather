import { Injectable } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import { config } from '../config';
import { localParts, toIso } from '../common/time';
import { AirQualityHour, AirQualitySnapshot } from '../domain/types';
import { fetchJson, ProviderError } from './http';

export const OPEN_METEO_AQ = 'open_meteo_air_quality';

interface RawAq {
  latitude: number;
  longitude: number;
  current?: { time: number; us_aqi?: number | null; pm2_5?: number | null; pm10?: number | null; nitrogen_dioxide?: number | null; ozone?: number | null };
  hourly_units?: Record<string, string>;
  hourly?: { time: number[]; us_aqi?: (number | null)[]; pm2_5?: (number | null)[]; pm10?: (number | null)[]; nitrogen_dioxide?: (number | null)[]; ozone?: (number | null)[] };
}

const VARS = 'us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone';
const CONCENTRATION_UNIT = 'μg/m³';

/** CAMS model air quality (not a station). station is always null for this adapter. */
@Injectable()
export class OpenMeteoAirQualityAdapter {
  readonly providerId = config.providerMode === 'fixture' ? 'fixture' : OPEN_METEO_AQ;

  async fetch(lat: number, lon: number, timezone: string): Promise<AirQualitySnapshot> {
    let raw: RawAq;
    if (config.providerMode === 'fixture') {
      raw = JSON.parse(fs.readFileSync(path.join(config.fixtureDir, 'open-meteo-air-quality.json'), 'utf8'));
    } else {
      const p = new URLSearchParams({
        latitude: lat.toFixed(4),
        longitude: lon.toFixed(4),
        current: VARS,
        hourly: VARS,
        forecast_days: '3',
        timezone,
        timeformat: 'unixtime',
      });
      if (config.openMeteo.apiKey) p.set('apikey', config.openMeteo.apiKey);
      raw = await fetchJson<RawAq>(OPEN_METEO_AQ, `${config.openMeteo.aqHost}/v1/air-quality?${p}`);
    }
    return parseAirQuality(raw, timezone);
  }
}

export function parseAirQuality(raw: RawAq, timezone: string): AirQualitySnapshot {
  if (!raw?.hourly || !Array.isArray(raw.hourly.time)) throw new ProviderError(OPEN_METEO_AQ, 'MALFORMED');
  const h = raw.hourly;
  const units = raw.hourly_units ?? {};
  const conc = (k: 'pm2_5' | 'pm10' | 'nitrogen_dioxide' | 'ozone') =>
    units[k] === undefined || units[k] === CONCENTRATION_UNIT || units[k] === 'µg/m³' ? h[k] : undefined;
  const pick = (arr: (number | null)[] | undefined, i: number) => {
    const v = arr?.[i];
    return typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null;
  };
  const hourly: AirQualityHour[] = h.time.map((t, i) => {
    const ms = t * 1000;
    const lp = localParts(ms, timezone);
    return {
      time: toIso(ms),
      localTime: lp.localTime,
      localDate: lp.localDate,
      usAqi: pick(h.us_aqi, i),
      pm25: pick(conc('pm2_5'), i),
      pm10: pick(conc('pm10'), i),
      no2: pick(conc('nitrogen_dioxide'), i),
      o3: pick(conc('ozone'), i),
    };
  });
  const c = raw.current;
  const val = (v: number | null | undefined) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null);
  return {
    current: c
      ? {
          validAt: toIso(c.time * 1000),
          time: toIso(c.time * 1000),
          usAqi: val(c.us_aqi),
          pm25: val(c.pm2_5),
          pm10: val(c.pm10),
          no2: val(c.nitrogen_dioxide),
          o3: val(c.ozone),
        }
      : null,
    hourly,
    fetchedAt: toIso(Date.now()),
    dataCoordinate: { latitude: raw.latitude, longitude: raw.longitude },
  };
}
