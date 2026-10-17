import { Injectable, Logger } from '@nestjs/common';
// 'all' = comprehensive timezone-boundary-builder data. The default set merges zones that agree
// since 1970 and would label Hà Nội as Asia/Jakarta.
import { find as findTimezones } from 'geo-tz/all';
import { ApiError, badRequest, notFound } from '../common/errors';
import { isValidTimezone } from '../common/time';
import { Location, LocationKind } from '../domain/types';
import { GEONAMES, GeoResult, OpenMeteoGeocodingAdapter } from '../providers';
import { geonamesLocationId, LocationRepository, uuidV5 } from './location.repository';

export interface SearchResult {
  location: Location;
  featureCode: string | null;
  population: number | null;
  admin2: string | null;
  source: 'catalog' | 'geocoding';
}

export interface ResolvedGps extends Location {
  /** The label is the nearest populated place; weather still uses the GPS coordinate. */
  nameApproximate: boolean;
  nearestPlaceDistanceKm: number | null;
  timezoneSource: 'timezone_boundary_builder' | 'nautical';
}

const MAX_RESULTS = 20;
const SUPPLEMENT_BUDGET_MS = 1500;
/** timezone-boundary-builder data version shipped with geo-tz (ODbL). */
export const TIMEZONE_DATASET = 'geo-tz@8.1.2/all (timezone-boundary-builder comprehensive, ODbL)';

@Injectable()
export class LocationsService {
  private readonly log = new Logger('Locations');

  constructor(
    private readonly repo: LocationRepository,
    private readonly geocoding: OpenMeteoGeocodingAdapter,
  ) {}

  async search(q: string, locale: string, limit: number, countryCode?: string): Promise<SearchResult[]> {
    const query = (q ?? '').trim();
    if (query.length < 2) throw badRequest('q', 'validation.minLength2');
    if (query.length > 100) throw badRequest('q', 'validation.maxLength100');
    if (countryCode !== undefined && !/^[A-Za-z]{2}$/.test(countryCode)) throw badRequest('countryCode', 'validation.countryCode');
    const count = Math.min(Math.max(Number.isFinite(limit) ? limit : 10, 1), MAX_RESULTS);
    const cc = countryCode?.toUpperCase();

    // 1) Server catalog first (spec §6.3).
    const out: SearchResult[] = (await this.repo.search(query, count, cc)).map((h) => ({
      location: h.location,
      featureCode: h.featureCode,
      population: h.population,
      admin2: h.admin2,
      source: 'catalog' as const,
    }));

    // 2) Online geocoding supplements what the catalog does not have.
    if (out.length < count) {
      const lang = /^[a-z]{2}$/.test(locale) ? locale : 'en';
      let raw: GeoResult[] = [];
      try {
        const lookup = this.geocoding.search(query, lang, count, cc);
        // With catalog hits in hand, the online supplement gets a short budget so a slow
        // provider never stalls search-as-you-type.
        raw = out.length
          ? await Promise.race([lookup, new Promise<GeoResult[]>((r) => setTimeout(() => r([]), SUPPLEMENT_BUDGET_MS))])
          : await lookup;
      } catch {
        if (!out.length) throw new ApiError(503, 'SEARCH_UNAVAILABLE', 'error.searchUnavailable', undefined, 30);
      }
      const seen = new Set(out.map((r) => r.location.locationId));
      for (const r of raw) {
        if (out.length >= count) break;
        if (!r.timezone || !isValidTimezone(r.timezone) || !validCoord(r.latitude, r.longitude)) continue;
        const id = geonamesLocationId(r.id);
        if (seen.has(id)) continue;
        seen.add(id);
        const loc = await this.repo.upsert(fromGeoResult(r), { featureCode: r.feature_code ?? null, population: r.population ?? null, admin2: r.admin2 ?? null });
        out.push({ location: loc, featureCode: r.feature_code ?? null, population: r.population ?? null, admin2: r.admin2 ?? null, source: 'geocoding' });
      }
    }
    return out;
  }

  /**
   * GPS → location. The IANA zone comes from timezone-boundary-builder polygons (point in
   * polygon), never from the device or the nearest city name.
   */
  async resolve(lat: number, lon: number, accuracyM: number | null): Promise<ResolvedGps> {
    if (!validCoord(lat, lon)) throw badRequest('latitude', 'validation.coordinate');
    if (accuracyM !== null && (!Number.isFinite(accuracyM) || accuracyM < 0)) throw badRequest('accuracy', 'validation.accuracy');
    const rLat = Math.round(lat * 1e4) / 1e4;
    const rLon = Math.round(lon * 1e4) / 1e4;

    let zones: string[];
    try {
      zones = findTimezones(rLat, rLon);
    } catch (e) {
      this.log.warn(`timezone lookup failed: ${(e as Error).message}`);
      zones = [];
    }
    // Disputed areas can return several zones; without a policy for that point we refuse to guess.
    if (zones.length !== 1 || !isValidTimezone(zones[0])) {
      throw new ApiError(422, 'TIMEZONE_UNRESOLVED', 'error.timezoneUnresolved');
    }
    const tz = zones[0];
    const nearest = await this.repo.nearestPlace(rLat, rLon, 30).catch(() => null);
    const loc = await this.repo.upsert({
      locationId: uuidV5(`gps:${rLat.toFixed(4)},${rLon.toFixed(4)}`),
      kind: 'gps',
      name: nearest?.location.name ?? null,
      countryCode: nearest?.location.countryCode ?? null,
      country: nearest?.location.country ?? null,
      admin1: nearest?.location.admin1 ?? null,
      latitude: rLat,
      longitude: rLon,
      timezone: tz,
      coordinateSource: 'gps',
      externalIds: [],
    });
    return {
      ...loc,
      nameApproximate: true,
      nearestPlaceDistanceKm: nearest?.distanceKm ?? null,
      timezoneSource: tz.startsWith('Etc/') ? 'nautical' : 'timezone_boundary_builder',
    };
  }

  async get(id: string): Promise<Location> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)) throw badRequest('locationId', 'validation.locationId');
    const loc = await this.repo.get(id);
    if (!loc) throw notFound('LOCATION_NOT_FOUND');
    void this.repo.touch([id]).catch(() => undefined);
    return loc;
  }

  async getMany(ids: string[]): Promise<Map<string, Location>> {
    const valid = ids.filter((id) => /^[0-9a-f-]{36}$/.test(id));
    const map = await this.repo.getMany(valid);
    void this.repo.touch([...map.keys()]).catch(() => undefined);
    return map;
  }

  /** Re-registers a place by its GeoNames id (e.g. a saved place unknown to a fresh server). */
  async registerExternal(provider: string, externalId: string, locale: string): Promise<Location> {
    if (provider !== GEONAMES || !/^\d{1,12}$/.test(externalId)) throw badRequest('externalId', 'validation.externalId');
    const existing = await this.repo.get(geonamesLocationId(externalId));
    if (existing) return existing;
    const r = await this.geocoding.getById(Number(externalId), /^[a-z]{2}$/.test(locale) ? locale : 'en');
    if (!r || !r.timezone || !isValidTimezone(r.timezone)) throw notFound('LOCATION_NOT_FOUND');
    return this.repo.upsert(fromGeoResult(r), { featureCode: r.feature_code ?? null, population: r.population ?? null, admin2: r.admin2 ?? null });
  }
}

export function validCoord(lat: number, lon: number): boolean {
  return Number.isFinite(lat) && Number.isFinite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

export function kindOf(featureCode: string | undefined | null): LocationKind {
  if (!featureCode) return 'place';
  if (featureCode.startsWith('PPL')) return 'city';
  if (featureCode.startsWith('ADM')) return 'administrative_area';
  return 'place';
}

export function fromGeoResult(r: GeoResult): Location {
  return {
    locationId: geonamesLocationId(r.id),
    kind: kindOf(r.feature_code),
    name: r.name,
    countryCode: r.country_code ?? null,
    country: r.country ?? null,
    admin1: r.admin1 ?? null,
    latitude: r.latitude,
    longitude: r.longitude,
    timezone: r.timezone!,
    coordinateSource: 'geocoding',
    externalIds: [{ provider: GEONAMES, externalId: String(r.id) }],
  };
}
