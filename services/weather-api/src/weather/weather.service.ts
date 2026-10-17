import { Injectable } from '@nestjs/common';
import { ApiError, badRequest } from '../common/errors';
import { addDays, isLocalDate, localDayStartMs, localParts, toIso } from '../common/time';
import {
  beaufort,
  BEAUFORT_TABLE_VERSION,
  compassLabel,
  feelsLabel,
  humidityLabel,
  median,
  minMax,
  nextShower,
  pressureTrend,
  round,
  RULES_VERSION,
  sumPrecipitation,
  usAqiCategory,
  uvCategory,
  visibilityCategory,
  windowAbove,
} from '../domain/rules';
import { CONDITION_MAPPING_VERSION } from '../domain/condition';
import { DailyRecord, HourlyRecord, Location, SCHEMA_VERSION, Section } from '../domain/types';
import { LocationsService } from '../locations/locations.service';
import { ForecastResult } from '../providers';
import { Loaded, section, SnapshotService, sourceOf, TTL, unsupported } from './snapshot.service';

const HOUR = 3_600_000;
export const METRICS = ['wind', 'rain', 'humidity', 'visibility', 'uv', 'pressure', 'feels-like'] as const;
export type Metric = (typeof METRICS)[number];

export interface Insight {
  insightId: string;
  type: 'rain' | 'uv' | 'aqi';
  sourceType: 'app_reminder';
  priority: number;
  validFrom: string;
  validTo: string | null;
  value: number | null;
  category: string | null;
  fromLocal: string | null;
  toLocal: string | null;
}

@Injectable()
export class WeatherService {
  private readonly lastManualRefresh = new Map<string, number>();

  constructor(
    private readonly locations: LocationsService,
    private readonly snapshots: SnapshotService,
  ) {}

  // ---------- shared helpers ----------

  private today(loc: Location, nowMs = Date.now()): string {
    return localParts(nowMs, loc.timezone).localDate;
  }

  private envelope(loc: Location, extra: Record<string, unknown>, warnings: string[] = []) {
    return {
      schemaVersion: SCHEMA_VERSION,
      generatedAt: toIso(Date.now()),
      location: loc,
      localDate: this.today(loc),
      ...extra,
      warnings,
      versions: { rules: RULES_VERSION, conditionMapping: CONDITION_MAPPING_VERSION },
    };
  }

  private forecastSource(f: Loaded<ForecastResult>, records: { time: string }[]) {
    const range = records.length ? { from: records[0].time, to: toIso(Date.parse(records[records.length - 1].time) + HOUR) } : undefined;
    return sourceOf(f, 'model', null, range);
  }

  private dateOrToday(loc: Location, f: ForecastResult, date?: string): string {
    const d = date ?? this.today(loc);
    if (!isLocalDate(d)) throw badRequest('date', 'validation.localDate');
    if (!f.snapshot.daily.some((x) => x.localDate === d)) {
      throw new ApiError(400, 'DATE_OUT_OF_HORIZON', 'error.dateOutOfHorizon', [{ field: 'date', messageKey: 'validation.horizon' }]);
    }
    return d;
  }

  private hoursOf(f: ForecastResult, localDate: string): HourlyRecord[] {
    return f.snapshot.hourly.filter((h) => h.localDate === localDate);
  }

  private currentStale(f: Loaded<ForecastResult>, nowMs: number): boolean {
    const c = f.value.snapshot.current;
    return f.stale || !c || nowMs - Date.parse(c.validAt) > TTL.currentMaxAge;
  }

  private dailyFrom(f: ForecastResult, fromDate: string, days: number): DailyRecord[] {
    return f.snapshot.daily.filter((d) => d.localDate >= fromDate).slice(0, days);
  }

  // ---------- Home ----------

  async home(locationId: string) {
    const loc = await this.locations.get(locationId);
    const nowMs = Date.now();
    const f = await this.snapshots.forecast(loc);
    const s = f.value.snapshot;
    const today = this.today(loc, nowMs);
    const hourFloor = Math.floor(nowMs / HOUR) * HOUR;
    const upcoming = s.hourly.filter((h) => Date.parse(h.time) >= hourFloor).slice(0, 25);
    const daily = this.dailyFrom(f.value, today, 10);
    const todayRec = daily.find((d) => d.localDate === today) ?? null;
    const cur = s.current;
    const curStale = this.currentStale(f, nowMs);

    const highlights = cur
      ? {
          feelsLike: feelsLabel(cur.temperatureC, cur.feelsLikeC),
          uvCategory: uvCategory(cur.uvIndex),
          windCompass: compassLabel(cur.windDirectionDeg, cur.windSpeedMs),
          beaufort: beaufort(cur.windSpeedMs),
          humidityLabel: humidityLabel(cur.humidityPct),
          visibilityCategory: visibilityCategory(cur.visibilityM),
          pressureTrend: pressureTrend(s.hourly, nowMs),
          todayPrecipitationMm: todayRec?.precipitationTotalMm ?? null,
          todayPrecipitationBasis: 'model_daily_sum',
        }
      : null;

    const aq = await this.snapshots.optional(
      () => this.snapshots.airQuality(loc),
      (l) => {
        const c = l.value.current;
        const data = c ? { ...c, standard: 'US_AQI', category: usAqiCategory(c.usAqi), station: null } : null;
        return section(data, sourceOf(l, 'model', c?.validAt ?? null), { stale: l.stale });
      },
    );

    const aurora = await this.snapshots.optional(
      () => this.snapshots.kp(),
      (l) => {
        const nowBin = this.currentKp(l.value, nowMs);
        return section(nowBin ? { kp: nowBin.kp, kind: nowBin.kind, binStart: nowBin.time, outlook: auroraOutlook(loc.latitude, nowBin.kp) } : null, sourceOf(l, 'model', nowBin?.time ?? null), { stale: l.stale });
      },
    );

    const insights = this.insights(f, aq, nowMs, today);

    return this.envelope(
      loc,
      {
        sections: {
          current: {
            ...section(cur, sourceOf(f, 'model', cur?.validAt ?? null), { stale: curStale }),
            reasonCode: curStale && cur ? (f.stale ? 'UPSTREAM_REFRESH_FAILED' : 'CURRENT_TOO_OLD') : cur ? null : 'NO_DATA',
          },
          today: section(todayRec, sourceOf(f, 'model', null, todayRec ? { from: todayRec.startAt, to: todayRec.endAt } : undefined), { stale: f.stale }),
          highlights: section(highlights, sourceOf(f, 'derived', cur?.validAt ?? null), { stale: curStale }),
          hourly: section(upcoming, this.forecastSource(f, upcoming), { stale: f.stale }),
          daily: { ...section(daily, sourceOf(f, 'model', null), { stale: f.stale }), horizonDays: daily.length },
          airQuality: aq,
          insights,
          officialAlerts: unsupported('COVERAGE_NOT_VERIFIED'),
          aurora,
          map: unsupported('MAP_PROVIDER_NOT_CONFIGURED'),
        },
        requestedCoordinate: s.requestedCoordinate,
        dataCoordinate: s.dataCoordinate,
      },
      f.value.warnings,
    );
  }

  /** Reminder rules (spec §11.2). Never produced from stale data; never labelled as an official alert. */
  private insights(f: Loaded<ForecastResult>, aq: Section<{ usAqi: number | null } & Record<string, unknown>>, nowMs: number, today: string): Section<Insight[]> {
    if (f.stale) return { status: 'stale', reasonCode: 'STALE_DATA_NO_REMINDERS', source: null, data: null };
    const out: Insight[] = [];
    const hours = f.value.snapshot.hourly;
    const hourFloor = Math.floor(nowMs / HOUR) * HOUR;

    const rain = hours.find((h) => {
      const t = Date.parse(h.time);
      return t > nowMs && t <= nowMs + 2 * HOUR && h.precipitationMm !== null && h.precipitationMm >= 0.2 && (h.rainProbabilityPct === null || h.rainProbabilityPct >= 50);
    });
    if (rain) {
      out.push({ insightId: `rain:${rain.time}`, type: 'rain', sourceType: 'app_reminder', priority: 1, validFrom: rain.intervalStartAt, validTo: rain.time, value: rain.precipitationMm, category: null, fromLocal: rain.localTime, toLocal: null });
    }

    const todayRemaining = hours.filter((h) => h.localDate === today && Date.parse(h.time) >= hourFloor);
    const uvWin = windowAbove(todayRemaining, 'uvIndex', 6);
    if (uvWin && Date.parse(uvWin.from) <= nowMs + 3 * HOUR) {
      out.push({ insightId: `uv:${today}:${uvCategory(uvWin.peak.value)}`, type: 'uv', sourceType: 'app_reminder', priority: 2, validFrom: uvWin.from, validTo: uvWin.to, value: uvWin.peak.value, category: uvCategory(uvWin.peak.value), fromLocal: uvWin.fromLocal, toLocal: uvWin.toLocal });
    }

    const aqi = (aq.data as { usAqi: number | null } | null)?.usAqi ?? null;
    if (aq.status === 'ready' && aqi !== null && aqi >= 151) {
      out.push({ insightId: `aqi:${today}:${usAqiCategory(aqi)}`, type: 'aqi', sourceType: 'app_reminder', priority: 3, validFrom: toIso(nowMs), validTo: null, value: aqi, category: usAqiCategory(aqi), fromLocal: null, toLocal: null });
    }

    const data = out.sort((a, b) => a.priority - b.priority).slice(0, 3);
    return section(data, sourceOf(f, 'derived', toIso(nowMs)), { emptyReason: 'NO_ACTIVE_INSIGHTS' });
  }

  private currentKp(bins: { time: string; kp: number; kind: string }[], nowMs: number) {
    let cur = null;
    for (const b of bins) if (Date.parse(b.time) <= nowMs) cur = b;
    return cur;
  }

  // ---------- Summaries ----------

  async summaries(ids: string[]) {
    if (!ids.length) throw badRequest('locationIds', 'validation.required');
    if (ids.length > 20) throw badRequest('locationIds', 'validation.max20');
    const nowMs = Date.now();
    const unique = [...new Set(ids)];
    const known = await this.locations.getMany(unique);
    const items = await Promise.all(
      unique.map(async (id) => {
        const loc = known.get(id);
        if (!loc) return { locationId: id, status: 'error', reasonCode: 'LOCATION_NOT_FOUND', location: null };
        try {
          const f = await this.snapshots.forecast(loc);
          const today = this.today(loc, nowMs);
          const d = f.value.snapshot.daily.find((x) => x.localDate === today) ?? null;
          const c = f.value.snapshot.current;
          return {
            locationId: id,
            status: this.currentStale(f, nowMs) ? 'stale' : 'ready',
            reasonCode: null,
            location: loc,
            localTime: localParts(nowMs, loc.timezone).localTime,
            temperatureC: c?.temperatureC ?? null,
            conditionCode: c?.conditionCode ?? 'UNKNOWN',
            isDay: c?.isDay ?? null,
            minC: d?.minC ?? null,
            maxC: d?.maxC ?? null,
            validAt: c?.validAt ?? null,
            source: sourceOf(f, 'model', c?.validAt ?? null),
          };
        } catch (e) {
          const code = e instanceof ApiError ? e.code : 'ERROR';
          return { locationId: id, status: 'error', reasonCode: code, location: loc };
        }
      }),
    );
    return { schemaVersion: SCHEMA_VERSION, generatedAt: toIso(nowMs), items };
  }

  // ---------- Hourly / daily ----------

  async hourly(locationId: string, date?: string, metric?: string) {
    if (metric !== undefined && !['temperature', 'rain', 'wind'].includes(metric)) throw badRequest('metric', 'validation.enum');
    const loc = await this.locations.get(locationId);
    const f = await this.snapshots.forecast(loc);
    const d = this.dateOrToday(loc, f.value, date);
    const records = this.hoursOf(f.value, d);
    const temp = minMax(records, 'temperatureC');
    const day = f.value.snapshot.daily.find((x) => x.localDate === d) ?? null;
    return this.envelope(
      loc,
      {
        date: d,
        metric: metric ?? 'temperature',
        availableDates: f.value.snapshot.daily.filter((x) => x.localDate >= this.today(loc)).map((x) => x.localDate),
        current: f.value.snapshot.current,
        summary: { temperature: temp, day },
        section: section(records, this.forecastSource(f, records), { stale: f.stale }),
      },
      f.value.warnings,
    );
  }

  async daily(locationId: string, days = 10) {
    if (!Number.isInteger(days) || days < 1 || days > 10) throw badRequest('days', 'validation.range1to10');
    const loc = await this.locations.get(locationId);
    const f = await this.snapshots.forecast(loc);
    const records = this.dailyFrom(f.value, this.today(loc), days);
    return this.envelope(
      loc,
      {
        requestedDays: days,
        horizonDays: records.length,
        overview: dailyOverview(records),
        section: section(records, sourceOf(f, 'model', null), { stale: f.stale }),
      },
      f.value.warnings,
    );
  }

  // ---------- Metrics ----------

  async metric(metric: string, locationId: string, date?: string, window?: string) {
    if (!(METRICS as readonly string[]).includes(metric)) throw badRequest('metric', 'validation.enum');
    const loc = await this.locations.get(locationId);
    const nowMs = Date.now();
    const f = await this.snapshots.forecast(loc);
    const d = this.dateOrToday(loc, f.value, date);
    const records = this.hoursOf(f.value, d);
    const s = f.value.snapshot;
    const cur = s.current;
    const today = this.today(loc, nowMs);
    let summary: Record<string, unknown>;

    switch (metric as Metric) {
      case 'wind': {
        const gust = minMax(records, 'windGustMs');
        const speed = minMax(records, 'windSpeedMs');
        const directions = records
          .filter((r) => [9, 12, 15, 18].includes(Number(r.localTime.slice(11, 13))))
          .map((r) => ({ time: r.time, localTime: r.localTime, directionDeg: r.windDirectionDeg, compass: compassLabel(r.windDirectionDeg, r.windSpeedMs), speedMs: r.windSpeedMs }));
        summary = {
          current: cur ? { speedMs: cur.windSpeedMs, gustMs: cur.windGustMs, directionDeg: cur.windDirectionDeg, compass: compassLabel(cur.windDirectionDeg, cur.windSpeedMs), validAt: cur.validAt, heightM: 10 } : null,
          peakGust: gust.max,
          peakSpeed: speed.max,
          beaufort: cur ? { force: beaufort(cur.windSpeedMs), tableVersion: BEAUFORT_TABLE_VERSION } : null,
          directions,
        };
        break;
      }
      case 'rain': {
        const w = window ?? 'today';
        if (!['today', '24h', '7d'].includes(w)) throw badRequest('window', 'validation.enum');
        const dayStart = localDayStartMs(today, loc.timezone);
        const hourFloor = Math.floor(nowMs / HOUR) * HOUR;
        const sinceMidnight = sumPrecipitation(s.hourly, dayStart, hourFloor);
        const todayAll = sumPrecipitation(s.hourly, dayStart, localDayStartMs(addDays(today, 1), loc.timezone));
        const next24 = sumPrecipitation(s.hourly, hourFloor, hourFloor + 24 * HOUR);
        const remainingToday = s.hourly.filter((h) => h.localDate === today && Date.parse(h.time) >= hourFloor);
        const week = this.dailyFrom(f.value, today, 7).map((x) => ({ localDate: x.localDate, totalMm: x.precipitationTotalMm, rainProbabilityMaxPct: x.rainProbabilityMaxPct }));
        summary = {
          window: w,
          basis: 'model_estimate',
          todaySoFar: sinceMidnight,
          todayTotal: todayAll,
          next24h: next24,
          chanceTodayMaxPct: minMax(remainingToday, 'rainProbabilityPct').max?.value ?? null,
          nextShower: nextShower(s.hourly, nowMs),
          nextShowerRule: { minAmountMm: 0.2, minProbabilityPct: 50, horizonHours: 48 },
          week,
        };
        const series =
          w === 'today'
            ? s.hourly.filter((h) => h.localDate === today)
            : w === '24h'
              ? s.hourly.filter((h) => Date.parse(h.time) >= hourFloor && Date.parse(h.time) < hourFloor + 24 * HOUR)
              : [];
        return this.envelope(loc, { metric, date: today, summary, section: section(series, this.forecastSource(f, series), { stale: f.stale, emptyReason: w === '7d' ? 'SEE_SUMMARY_WEEK' : 'NO_DATA' }) }, f.value.warnings);
      }
      case 'humidity': {
        summary = {
          current: cur ? { humidityPct: cur.humidityPct, dewPointC: cur.dewPointC, label: humidityLabel(cur.humidityPct), validAt: cur.validAt } : null,
          humidity: minMax(records, 'humidityPct'),
          dewPoint: minMax(records, 'dewPointC'),
          thresholds: { lowBelow: 30, moderateBelow: 60, highUpTo: 80 },
        };
        break;
      }
      case 'visibility': {
        const tomorrow = addDays(today, 1);
        const tHours = s.hourly.filter((h) => h.localDate === tomorrow && h.isDay === true);
        const med = median(tHours.map((h) => h.visibilityM));
        summary = {
          current: cur ? { visibilityM: cur.visibilityM, category: visibilityCategory(cur.visibilityM), validAt: cur.validAt, humidityPct: cur.humidityPct, cloudCoverPct: cur.cloudCoverPct } : null,
          visibility: minMax(records, 'visibilityM'),
          tomorrow: { localDate: tomorrow, visibilityM: med, category: visibilityCategory(med), method: 'median_daytime_hours', hoursUsed: tHours.filter((h) => h.visibilityM !== null).length, range: minMax(tHours, 'visibilityM') },
        };
        break;
      }
      case 'uv': {
        const hourFloor = Math.floor(nowMs / HOUR) * HOUR;
        const nowRec = s.hourly.find((h) => Date.parse(h.time) === hourFloor) ?? null;
        const peak = minMax(records, 'uvIndex').max;
        const day = s.daily.find((x) => x.localDate === d) ?? null;
        summary = {
          current: d === today ? { uvIndex: cur?.uvIndex ?? nowRec?.uvIndex ?? null, category: uvCategory(cur?.uvIndex ?? nowRec?.uvIndex ?? null), validAt: cur?.validAt ?? nowRec?.time ?? null } : null,
          dailyMax: day ? { uvIndex: day.uvIndexMax, category: uvCategory(day.uvIndexMax) } : null,
          peak,
          strongWindow: windowAbove(records, 'uvIndex', 6),
          strongThreshold: 6,
          hourlyAvailable: records.some((r) => r.uvIndex !== null),
        };
        break;
      }
      case 'pressure': {
        summary = {
          current: cur ? { seaLevelPressureHpa: cur.seaLevelPressureHpa, surfacePressureHpa: cur.surfacePressureHpa, validAt: cur.validAt } : null,
          kind: 'sea_level',
          trend: d === today ? pressureTrend(s.hourly, nowMs) : null,
          range: minMax(records, 'seaLevelPressureHpa'),
        };
        break;
      }
      case 'feels-like': {
        summary = {
          current: cur ? { actualC: cur.temperatureC, feelsLikeC: cur.feelsLikeC, ...feelsLabel(cur.temperatureC, cur.feelsLikeC), validAt: cur.validAt, algorithm: 'open_meteo_apparent_temperature' } : null,
          actual: minMax(records, 'temperatureC'),
          feelsLike: minMax(records, 'feelsLikeC'),
          similarThresholdC: 0.5,
        };
        break;
      }
    }
    return this.envelope(loc, { metric, date: d, summary: summary!, section: section(records, this.forecastSource(f, records), { stale: f.stale }) }, f.value.warnings);
  }

  // ---------- Refresh ----------

  async refresh(locationId: string, scope: string) {
    if (!['weather', 'air_quality', 'all'].includes(scope)) throw badRequest('scope', 'validation.enum');
    const loc = await this.locations.get(locationId);
    const key = `${locationId}:${scope}`;
    const last = this.lastManualRefresh.get(key) ?? 0;
    const nowMs = Date.now();
    const cooldownMs = 60_000;
    if (nowMs - last < cooldownMs) {
      return { refreshed: false, reasonCode: 'COOLDOWN', nextAllowedAt: toIso(last + cooldownMs) };
    }
    this.lastManualRefresh.set(key, nowMs);
    const tasks: Promise<unknown>[] = [];
    if (scope !== 'air_quality') tasks.push(this.snapshots.forecast(loc, true));
    if (scope !== 'weather') tasks.push(this.snapshots.airQuality(loc, true).catch(() => null));
    await Promise.all(tasks);
    return { refreshed: true, reasonCode: null, nextAllowedAt: toIso(nowMs + cooldownMs) };
  }
}

/** Rule-based 10-day overview (versioned, localized by the client from codes). */
export function dailyOverview(days: DailyRecord[]) {
  const first = days.slice(0, 3).map((d) => d.maxC).filter((x): x is number => x !== null);
  let trend: 'warming' | 'cooling' | 'steady' | null = null;
  if (first.length >= 2) {
    const delta = first[first.length - 1] - first[0];
    trend = delta >= 2 ? 'warming' : delta <= -2 ? 'cooling' : 'steady';
  }
  const rainyDays = days.filter((d) => (d.rainProbabilityMaxPct !== null && d.rainProbabilityMaxPct >= 50) || (d.precipitationTotalMm !== null && d.precipitationTotalMm >= 1)).length;
  const maxes = days.map((d) => d.maxC).filter((x): x is number => x !== null);
  return {
    rulesVersion: RULES_VERSION,
    trend,
    rainyDays,
    horizonDays: days.length,
    averageMaxC: maxes.length ? round(maxes.reduce((a, b) => a + b, 0) / maxes.length, 1) : null,
  };
}

/** Qualitative, experimental outlook. Not a probability. */
export function auroraOutlook(lat: number, kp: number): 'unlikely' | 'possible_high_latitude' | 'possible' {
  const absLat = Math.abs(lat);
  if (absLat >= 60 && kp >= 3) return 'possible';
  if (absLat >= 50 && kp >= 6) return 'possible';
  if (absLat >= 55) return 'possible_high_latitude';
  return 'unlikely';
}
