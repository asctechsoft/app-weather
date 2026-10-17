import { Injectable, Logger } from '@nestjs/common';
import { Cache, RedisTtlCache, TtlCache } from '../common/cache';
import { RedisService } from '../common/redis';
import { ApiError } from '../common/errors';
import { toIso } from '../common/time';
import { AirQualitySnapshot, DataKind, Location, Section, SectionStatus, SourceMeta } from '../domain/types';
import { ForecastResult, KpBin, NoaaSwpcAdapter, OpenMeteoAirQualityAdapter, OpenMeteoForecastAdapter, ProviderError } from '../providers';

const MIN = 60_000;

/** Cache policy (spec §10.4, proposed starting values). */
export const TTL = {
  forecast: { ttl: 15 * MIN, staleCap: 6 * 60 * MIN },
  currentMaxAge: 2 * 60 * MIN,
  airQuality: { ttl: 60 * MIN, staleCap: 3 * 60 * MIN },
  noaa: { ttl: 5 * MIN, staleCap: 30 * MIN },
};

export interface Loaded<T> {
  value: T;
  providerId: string;
  fetchedAtMs: number;
  stale: boolean;
  ttlMs: number;
}

/** Fetches provider snapshots through the shared cache; one snapshot feeds Home and every detail screen. */
@Injectable()
export class SnapshotService {
  private readonly log = new Logger('Snapshot');
  readonly cache: Cache;

  constructor(
    private readonly forecastAdapter: OpenMeteoForecastAdapter,
    private readonly aqAdapter: OpenMeteoAirQualityAdapter,
    private readonly noaa: NoaaSwpcAdapter,
    redis: RedisService,
  ) {
    this.cache = redis.client ? new RedisTtlCache(redis.client) : new TtlCache();
  }

  private gridKey(loc: Location): string {
    return `${loc.latitude.toFixed(4)},${loc.longitude.toFixed(4)}:${loc.timezone}`;
  }

  async forecast(loc: Location, force = false): Promise<Loaded<ForecastResult>> {
    const key = `forecast:v1:${this.forecastAdapter.providerId}:${this.gridKey(loc)}`;
    try {
      const r = await this.cache.getOrLoad(key, TTL.forecast.ttl, TTL.forecast.staleCap, () => this.forecastAdapter.fetch(loc.latitude, loc.longitude, loc.timezone), { forceRefresh: force });
      return { value: r.value, providerId: this.forecastAdapter.providerId, fetchedAtMs: r.storedAt, stale: r.stale, ttlMs: TTL.forecast.ttl };
    } catch (e) {
      this.log.warn(`forecast failed: ${(e as Error).message}`);
      throw new ApiError(503, 'UPSTREAM_UNAVAILABLE', 'error.upstreamUnavailable', undefined, 60);
    }
  }

  async airQuality(loc: Location, force = false): Promise<Loaded<AirQualitySnapshot>> {
    const key = `aq:v1:${this.aqAdapter.providerId}:${this.gridKey(loc)}`;
    const r = await this.cache.getOrLoad(key, TTL.airQuality.ttl, TTL.airQuality.staleCap, () => this.aqAdapter.fetch(loc.latitude, loc.longitude, loc.timezone), { forceRefresh: force });
    return { value: r.value, providerId: this.aqAdapter.providerId, fetchedAtMs: r.storedAt, stale: r.stale, ttlMs: TTL.airQuality.ttl };
  }

  async kp(): Promise<Loaded<KpBin[]>> {
    const r = await this.cache.getOrLoad('noaa:kp:v1', TTL.noaa.ttl, TTL.noaa.staleCap, () => this.noaa.kpForecast());
    return { value: r.value, providerId: this.noaa.providerId, fetchedAtMs: r.storedAt, stale: r.stale, ttlMs: TTL.noaa.ttl };
  }

  /** Wraps an optional section so one provider failure never blanks the whole response. */
  async optional<T, R>(load: () => Promise<Loaded<T>>, build: (l: Loaded<T>) => Section<R>): Promise<Section<R>> {
    try {
      return build(await load());
    } catch (e) {
      const reason = e instanceof ProviderError ? `PROVIDER_${e.reasonCode}` : 'PROVIDER_ERROR';
      this.log.warn(`optional section failed: ${(e as Error).message}`);
      return { status: 'error', reasonCode: reason, source: null, data: null };
    }
  }
}

export function sourceOf(l: Loaded<unknown>, dataKind: DataKind, validAt: string | null, validRange?: { from: string; to: string }): SourceMeta {
  return {
    providerId: l.providerId,
    dataKind,
    validAt,
    validRange: validRange ?? null,
    fetchedAt: toIso(l.fetchedAtMs),
    expiresAt: toIso(l.fetchedAtMs + l.ttlMs),
    modelRunAt: null,
  };
}

export function section<T>(data: T | null, source: SourceMeta | null, opts: { stale?: boolean; emptyReason?: string } = {}): Section<T> {
  const isEmpty = data === null || (Array.isArray(data) && data.length === 0);
  const status: SectionStatus = isEmpty ? 'empty' : opts.stale ? 'stale' : 'ready';
  return {
    status,
    reasonCode: isEmpty ? opts.emptyReason ?? 'NO_DATA' : opts.stale ? 'UPSTREAM_REFRESH_FAILED' : null,
    source,
    data,
  };
}

export function unsupported(reasonCode: string): Section<never> {
  return { status: 'unsupported', reasonCode, source: null, data: null };
}
