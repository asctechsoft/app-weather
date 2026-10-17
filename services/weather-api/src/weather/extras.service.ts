import { Injectable } from '@nestjs/common';
import { ApiError, badRequest } from '../common/errors';
import { addDays, isLocalDate, localDayStartMs, localParts, toIso } from '../common/time';
import { minMax, usAqiCategory } from '../domain/rules';
import { AirQualityHour, SCHEMA_VERSION } from '../domain/types';
import { LocationsService } from '../locations/locations.service';
import { ASTRONOMY_ALGORITHM, moonInfo, sunEvents, upcomingPhases } from '../providers';
import { section, SnapshotService, sourceOf } from './snapshot.service';
import { auroraOutlook } from './weather.service';

/** AQ01, ASTRO01 and AUR01 — each section keeps its own provider and time. */
@Injectable()
export class ExtrasService {
  constructor(
    private readonly locations: LocationsService,
    private readonly snapshots: SnapshotService,
  ) {}

  async airQuality(locationId: string, date?: string) {
    const loc = await this.locations.get(locationId);
    const today = localParts(Date.now(), loc.timezone).localDate;
    const d = date ?? today;
    if (!isLocalDate(d)) throw badRequest('date', 'validation.localDate');
    let l;
    try {
      l = await this.snapshots.airQuality(loc);
    } catch {
      throw new ApiError(503, 'UPSTREAM_UNAVAILABLE', 'error.upstreamUnavailable', undefined, 60);
    }
    const hours = l.value.hourly.filter((h) => h.localDate === d);
    const tomorrow = addDays(today, 1);
    const tHours = l.value.hourly.filter((h) => h.localDate === tomorrow);
    const tMax = maxBy(tHours, 'usAqi');
    const c = l.value.current;
    return {
      schemaVersion: SCHEMA_VERSION,
      generatedAt: toIso(Date.now()),
      location: loc,
      localDate: today,
      date: d,
      standard: 'US_AQI',
      station: null,
      stationSupport: 'unsupported',
      dataCoordinate: l.value.dataCoordinate,
      current: section(c ? { ...c, category: usAqiCategory(c.usAqi) } : null, sourceOf(l, 'model', c?.validAt ?? null), { stale: l.stale }),
      tomorrow: section(tMax ? { localDate: tomorrow, maxUsAqi: tMax.usAqi, at: tMax.time, localTime: tMax.localTime, category: usAqiCategory(tMax.usAqi), method: 'daily_max_hourly' } : null, sourceOf(l, 'model', null), { stale: l.stale }),
      hourly: section(hours, sourceOf(l, 'model', null), { stale: l.stale }),
      concentrationUnit: 'μg/m³',
    };
  }

  async astronomy(locationId: string, date?: string) {
    const loc = await this.locations.get(locationId);
    const nowMs = Date.now();
    const today = localParts(nowMs, loc.timezone).localDate;
    const d = date ?? today;
    if (!isLocalDate(d)) throw badRequest('date', 'validation.localDate');
    if (d < addDays(today, -1) || d > addDays(today, 30)) throw new ApiError(400, 'DATE_OUT_OF_HORIZON', 'error.dateOutOfHorizon', [{ field: 'date', messageKey: 'validation.horizon' }]);
    const start = localDayStartMs(d, loc.timezone);
    const end = localDayStartMs(addDays(d, 1), loc.timezone);
    const sun = sunEvents(loc.latitude, loc.longitude, start, end);
    const atMs = d === today ? nowMs : Math.round((start + end) / 2);
    const moon = moonInfo(loc.latitude, loc.longitude, start, end, atMs);

    // Prefer the forecast provider's sunrise/sunset so Home and Sun & moon agree.
    let sunrise = { at: sun.sunriseAt, providerId: 'computed' };
    let sunset = { at: sun.sunsetAt, providerId: 'computed' };
    try {
      const f = await this.snapshots.forecast(loc);
      const day = f.value.snapshot.daily.find((x) => x.localDate === d);
      if (day) {
        sunrise = { at: day.sunriseAt, providerId: f.providerId };
        sunset = { at: day.sunsetAt, providerId: f.providerId };
      }
    } catch {
      /* keep computed */
    }
    const daylightSeconds = sunrise.at && sunset.at ? Math.round((Date.parse(sunset.at) - Date.parse(sunrise.at)) / 1000) : null;
    const computedSource = { providerId: 'computed', dataKind: 'computed' as const, validAt: null, validRange: { from: toIso(start), to: toIso(end) }, fetchedAt: toIso(nowMs), expiresAt: null, algorithm: ASTRONOMY_ALGORITHM };

    return {
      schemaVersion: SCHEMA_VERSION,
      generatedAt: toIso(nowMs),
      location: loc,
      localDate: today,
      date: d,
      sun: {
        status: 'ready',
        reasonCode: null,
        source: { ...computedSource, sunriseSunsetProviderId: sunrise.providerId },
        data: {
          sunriseAt: sunrise.at,
          sunsetAt: sunset.at,
          eventStatus: sunrise.at || sunset.at ? 'occurs' : sun.status,
          daylightSeconds,
          solarNoonAt: sun.solarNoonAt,
          civilDawnAt: sun.civilDawnAt,
          civilDuskAt: sun.civilDuskAt,
        },
      },
      moon: {
        status: 'ready',
        reasonCode: null,
        source: computedSource,
        data: { ...moon, upcomingPhases: upcomingPhases(atMs, loc.timezone, 4) },
      },
    };
  }

  async aurora(locationId: string, hemisphere?: string) {
    const h = hemisphere ?? 'north';
    if (!['north', 'south'].includes(h)) throw badRequest('hemisphere', 'validation.enum');
    const loc = await this.locations.get(locationId);
    const nowMs = Date.now();
    let kpSection;
    let nowKp: number | null = null;
    try {
      const l = await this.snapshots.kp();
      let cur = null;
      for (const b of l.value) if (Date.parse(b.time) <= nowMs) cur = b;
      nowKp = cur?.kp ?? null;
      const upcoming = l.value.filter((b) => Date.parse(b.time) + 3 * 3_600_000 > nowMs).slice(0, 8);
      kpSection = section({ current: cur, forecast: upcoming, scope: 'global_planetary' }, sourceOf(l, 'model', cur?.time ?? null), { stale: l.stale });
    } catch {
      kpSection = { status: 'error', reasonCode: 'PROVIDER_ERROR', source: null, data: null };
    }

    // Night window and cloud cover come from the weather snapshot (separate source).
    let night = null;
    try {
      const f = await this.snapshots.forecast(loc);
      const s = f.value.snapshot;
      const today = localParts(nowMs, loc.timezone).localDate;
      const tonightHours = s.hourly.filter((x) => Date.parse(x.time) >= nowMs - 3_600_000 && Date.parse(x.time) < nowMs + 24 * 3_600_000 && x.isDay === false);
      const today_ = s.daily.find((x) => x.localDate === today);
      const tomorrow_ = s.daily.find((x) => x.localDate === addDays(today, 1));
      night = section(
        {
          darkFrom: today_?.sunsetAt ?? null,
          darkTo: tomorrow_?.sunriseAt ?? null,
          cloudCover: minMax(tonightHours, 'cloudCoverPct'),
          hours: tonightHours.map((x) => ({ time: x.time, localTime: x.localTime, cloudCoverPct: x.cloudCoverPct })),
        },
        sourceOf(f, 'model', null),
        { stale: f.stale },
      );
    } catch {
      night = { status: 'error', reasonCode: 'PROVIDER_ERROR', source: null, data: null };
    }

    return {
      schemaVersion: SCHEMA_VERSION,
      generatedAt: toIso(nowMs),
      location: loc,
      hemisphere: h,
      kp: kpSection,
      night,
      localOutlook: {
        experimental: true,
        value: nowKp === null ? null : auroraOutlook(loc.latitude, nowKp),
        method: 'qualitative_latitude_kp_v1',
      },
      alertsSupport: 'unsupported',
    };
  }
}

function maxBy(rows: AirQualityHour[], key: 'usAqi'): AirQualityHour | null {
  let best: AirQualityHour | null = null;
  for (const r of rows) {
    const v = r[key];
    if (v === null) continue;
    if (!best || v > (best[key] as number)) best = r;
  }
  return best;
}
