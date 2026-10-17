import { Injectable } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import { config } from '../config';
import { fold } from '../locations/location.repository';
import { fetchJson } from './http';

export const OPEN_METEO_GEOCODING = 'open_meteo_geocoding';
/** Open-Meteo geocoding results are GeoNames records; the id is the GeoNames id. */
export const GEONAMES = 'geonames';

export interface GeoResult {
  id: number;
  name: string;
  latitude: number;
  longitude: number;
  elevation?: number;
  feature_code?: string;
  country_code?: string;
  country?: string;
  admin1?: string;
  admin2?: string;
  timezone?: string;
  population?: number;
}

@Injectable()
export class OpenMeteoGeocodingAdapter {
  async search(q: string, language: string, count: number, countryCode?: string): Promise<GeoResult[]> {
    if (config.providerMode === 'fixture') {
      const all: GeoResult[] = JSON.parse(fs.readFileSync(path.join(config.fixtureDir, 'open-meteo-geocoding.json'), 'utf8')).results ?? [];
      const needle = fold(q);
      return all.filter((r) => fold(r.name).includes(needle)).slice(0, count);
    }
    const p = new URLSearchParams({ name: q, count: String(count), language, format: 'json' });
    if (countryCode) p.set('countryCode', countryCode);
    if (config.openMeteo.apiKey) p.set('apikey', config.openMeteo.apiKey);
    const res = await fetchJson<{ results?: GeoResult[] }>(OPEN_METEO_GEOCODING, `${config.openMeteo.geocodingHost}/v1/search?${p}`);
    return res.results ?? [];
  }

  async getById(id: number, language: string): Promise<GeoResult | null> {
    if (config.providerMode === 'fixture') {
      const all: GeoResult[] = JSON.parse(fs.readFileSync(path.join(config.fixtureDir, 'open-meteo-geocoding.json'), 'utf8')).results ?? [];
      return all.find((r) => r.id === id) ?? null;
    }
    const p = new URLSearchParams({ id: String(id), language });
    if (config.openMeteo.apiKey) p.set('apikey', config.openMeteo.apiKey);
    try {
      return await fetchJson<GeoResult>(OPEN_METEO_GEOCODING, `${config.openMeteo.geocodingHost}/v1/get?${p}`);
    } catch {
      return null;
    }
  }
}

/** Diacritic folding shared with the catalog (alias_folded). */
export { fold } from '../locations/location.repository';
