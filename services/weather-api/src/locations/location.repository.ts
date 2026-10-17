import { Injectable } from '@nestjs/common';
import { createHash } from 'crypto';
import { PoolClient } from 'pg';
import { Db } from '../db/db';
import { Location, LocationKind } from '../domain/types';

/** RFC 4122 v5 namespace for SkyWeather location IDs (stable across imports and restarts). */
const NAMESPACE = 'b3f1c3e2-6a0e-5d4b-9b8e-3c2a1f0e9d7c';

export function uuidV5(name: string, namespace = NAMESPACE): string {
  const ns = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const hash = createHash('sha1').update(Buffer.concat([ns, Buffer.from(name, 'utf8')])).digest();
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const h = hash.subarray(0, 16).toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/** GeoNames id → internal id. Catalog import and geocoding fallback share it, so no duplicates. */
export const geonamesLocationId = (geonameId: string | number) => uuidV5(`geonames:${geonameId}`);

/** Lowercase + strip diacritics (Hà Nội → ha noi, Đà Nẵng → da nang). Mirrors alias_folded. */
export function fold(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[đĐ]/g, 'd')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

export interface CatalogHit {
  location: Location;
  population: number | null;
  featureCode: string | null;
  admin2: string | null;
  matched: string;
  score: number;
}

interface Row {
  location_id: string;
  kind: LocationKind;
  name: string | null;
  country_code: string | null;
  country_name: string | null;
  admin1_name: string | null;
  admin2_name: string | null;
  latitude: number;
  longitude: number;
  timezone: string;
  coordinate_source: Location['coordinateSource'];
  feature_code: string | null;
  population: string | null;
  external_ids: { provider: string; externalId: string }[] | null;
}

const SELECT = `
  SELECT l.location_id, l.kind, l.name, l.country_code, c.name AS country_name, l.admin1_name, l.admin2_name,
         l.latitude, l.longitude, l.timezone, l.coordinate_source, l.feature_code, l.population::text AS population,
         (SELECT json_agg(json_build_object('provider', e.provider, 'externalId', e.external_id))
            FROM location_external_ids e WHERE e.location_id = l.location_id) AS external_ids
    FROM locations l LEFT JOIN countries c ON c.code = l.country_code`;

function toLocation(r: Row): Location {
  return {
    locationId: r.location_id,
    kind: r.kind,
    name: r.name,
    countryCode: r.country_code?.trim() ?? null,
    country: r.country_name,
    admin1: r.admin1_name,
    latitude: Number(r.latitude),
    longitude: Number(r.longitude),
    timezone: r.timezone,
    coordinateSource: r.coordinate_source,
    externalIds: r.external_ids ?? [],
  };
}

@Injectable()
export class LocationRepository {
  constructor(private readonly db: Db) {}

  async get(id: string): Promise<Location | null> {
    const r = await this.db.one<Row>(`${SELECT} WHERE l.location_id = $1`, [id]);
    return r ? toLocation(r) : null;
  }

  async getMany(ids: string[]): Promise<Map<string, Location>> {
    if (!ids.length) return new Map();
    const rows = await this.db.query<Row>(`${SELECT} WHERE l.location_id = ANY($1::uuid[])`, [ids]);
    return new Map(rows.map((r) => [r.location_id, toLocation(r)]));
  }

  /**
   * Inserts or refreshes a location. An existing row keeps its coordinate: a rename or a
   * provider update must never move a forecast point that users have saved.
   */
  async upsert(loc: Location, extra: { featureCode?: string | null; population?: number | null; admin2?: string | null } = {}, client?: PoolClient): Promise<Location> {
    const q = client ? client.query.bind(client) : this.db.pool.query.bind(this.db.pool);
    await q(
      `INSERT INTO locations (location_id, kind, name, country_code, admin1_name, admin2_name, latitude, longitude, timezone, coordinate_source, feature_code, population)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT (location_id) DO UPDATE SET
         name = COALESCE(EXCLUDED.name, locations.name),
         admin1_name = COALESCE(EXCLUDED.admin1_name, locations.admin1_name),
         admin2_name = COALESCE(EXCLUDED.admin2_name, locations.admin2_name),
         feature_code = COALESCE(EXCLUDED.feature_code, locations.feature_code),
         population = COALESCE(EXCLUDED.population, locations.population),
         updated_at = now()`,
      [loc.locationId, loc.kind, loc.name, loc.countryCode, loc.admin1, extra.admin2 ?? null, loc.latitude, loc.longitude, loc.timezone, loc.coordinateSource, extra.featureCode ?? null, extra.population ?? null],
    );
    if (loc.countryCode && loc.country) {
      await q(`INSERT INTO countries (code, name) VALUES ($1, $2) ON CONFLICT (code) DO NOTHING`, [loc.countryCode, loc.country]);
    }
    for (const e of loc.externalIds) {
      await q(`INSERT INTO location_external_ids (provider, external_id, location_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`, [e.provider, e.externalId, loc.locationId]);
    }
    if (loc.name) {
      await q(
        `INSERT INTO location_aliases (location_id, locale, alias, alias_folded, is_preferred) VALUES ($1,'und',$2,$3,true) ON CONFLICT DO NOTHING`,
        [loc.locationId, loc.name, fold(loc.name)],
      );
    }
    return (await this.get(loc.locationId))!;
  }

  /**
   * Catalog search: diacritic-insensitive prefix + trigram similarity on aliases,
   * ranked by match quality then population. One row per location.
   */
  async search(query: string, limit: number, countryCode?: string): Promise<CatalogHit[]> {
    const q = fold(query);
    // Escape LIKE wildcards in user input before appending the prefix wildcard.
    const prefix = `${q.replace(/[\\%_]/g, (c) => '\\' + c)}%`;
    const rows = await this.db.query<Row & { matched: string; score: number }>(
      `WITH hits AS (
         SELECT a.location_id, a.alias AS matched,
                (CASE WHEN a.alias_folded = $1 THEN 3 WHEN a.alias_folded LIKE $2 THEN 2 ELSE 0 END)
                  + similarity(a.alias_folded, $1) AS score
           FROM location_aliases a
          -- Prefix matches always; fuzzy matches only for longer queries and close spellings,
          -- otherwise short queries ("ha noi") pull in unrelated places.
          WHERE a.alias_folded LIKE $2
             OR (length($1) >= 4 AND length(a.alias_folded) >= 4 AND a.alias_folded % $1 AND similarity(a.alias_folded, $1) >= 0.6)
       ), best AS (
         SELECT DISTINCT ON (location_id) location_id, matched, score
           FROM hits ORDER BY location_id, score DESC
       ), loc AS (${SELECT} WHERE l.retired_at IS NULL)
       SELECT loc.*, best.matched, best.score
         FROM best JOIN loc ON loc.location_id = best.location_id
        WHERE ($3::text IS NULL OR loc.country_code = $3)
        ORDER BY best.score DESC, loc.population::bigint DESC NULLS LAST
        LIMIT $4`,
      [q, prefix, countryCode ?? null, limit],
    );
    return rows.map((r) => ({
      location: toLocation(r),
      population: r.population === null ? null : Number(r.population),
      featureCode: r.feature_code,
      admin2: r.admin2_name,
      matched: r.matched,
      score: Number(r.score),
    }));
  }

  /** Nearest populated catalog place within `radiusKm` (approximate label for a GPS point). */
  async nearestPlace(lat: number, lon: number, radiusKm = 30): Promise<{ location: Location; distanceKm: number } | null> {
    const dLat = radiusKm / 111.32;
    const dLon = radiusKm / (111.32 * Math.max(Math.cos((lat * Math.PI) / 180), 0.01));
    const row = await this.db.one<Row & { dist: number }>(
      `WITH loc AS (${SELECT}
               WHERE l.in_catalog AND l.retired_at IS NULL AND l.kind = 'city'
                 AND l.latitude BETWEEN $3 AND $4 AND l.longitude BETWEEN $5 AND $6)
       SELECT loc.*, earth_distance(ll_to_earth($1, $2), ll_to_earth(loc.latitude, loc.longitude)) AS dist
         FROM loc ORDER BY dist ASC LIMIT 1`,
      [lat, lon, lat - dLat, lat + dLat, lon - dLon, lon + dLon],
    );
    if (!row || row.dist > radiusKm * 1000) return null;
    return { location: toLocation(row), distanceKm: Math.round(row.dist / 100) / 10 };
  }

  async touch(ids: string[]): Promise<void> {
    if (!ids.length) return;
    await this.db.query(`UPDATE locations SET last_requested_at = now() WHERE location_id = ANY($1::uuid[]) AND (last_requested_at IS NULL OR last_requested_at < now() - interval '5 minutes')`, [ids]);
  }

  /** Locations requested recently — the worker only prefetches places people actually use. */
  async recentlyRequested(sinceHours: number, limit: number): Promise<Location[]> {
    const rows = await this.db.query<Row>(`${SELECT} WHERE l.last_requested_at > now() - make_interval(hours => $1) ORDER BY l.last_requested_at DESC LIMIT $2`, [sinceHours, limit]);
    return rows.map(toLocation);
  }
}
