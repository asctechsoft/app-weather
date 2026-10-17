import { Body, Controller, Get, Headers, HttpCode, Post, Query, Req, Res } from '@nestjs/common';
import { createHash, randomUUID } from 'crypto';
import type { Response } from 'express';
import { config } from '../config';
import { ApiError, badRequest } from '../common/errors';
import { RedisService } from '../common/redis';
import { toIso } from '../common/time';
import { Db } from '../db/db';
import { AuthedRequest, Public } from '../installations/auth.guard';
import { LocationsService } from '../locations/locations.service';

/** Source/attribution registry. Only providers actually wired in this build are "active". */
const SOURCES = [
  { group: 'weather', providerId: 'open_meteo', name: 'Open-Meteo Forecast API', dataKind: 'model', coverage: 'global', status: 'active', license: 'CC BY 4.0', url: 'https://open-meteo.com/', attribution: 'Weather data by Open-Meteo.com' },
  { group: 'air_quality', providerId: 'open_meteo_air_quality', name: 'Open-Meteo Air Quality API (CAMS)', dataKind: 'model', coverage: 'global', status: 'active', license: 'CC BY 4.0', url: 'https://open-meteo.com/en/docs/air-quality-api', attribution: 'Air quality: Open-Meteo / Copernicus Atmosphere Monitoring Service' },
  { group: 'places', providerId: 'geonames', name: 'GeoNames via Open-Meteo Geocoding', dataKind: 'catalog', coverage: 'global', status: 'active', license: 'CC BY 4.0', url: 'https://www.geonames.org/', attribution: 'Place names: GeoNames' },
  { group: 'astronomy', providerId: 'computed', name: 'SunCalc 1.9.0 (computed)', dataKind: 'computed', coverage: 'global', status: 'active', license: 'BSD-2-Clause', url: 'https://github.com/mourner/suncalc', attribution: 'Sun & moon computed with SunCalc' },
  { group: 'aurora', providerId: 'noaa_swpc', name: 'NOAA Space Weather Prediction Center', dataKind: 'model', coverage: 'global_index', status: 'active', license: 'Public domain (US Government)', url: 'https://www.swpc.noaa.gov/', attribution: 'Kp index: NOAA SWPC' },
  { group: 'alerts', providerId: null, name: null, dataKind: 'official', coverage: 'none', status: 'not_configured', license: null, url: null, attribution: null },
  { group: 'radar', providerId: null, name: null, dataKind: 'observation', coverage: 'none', status: 'not_configured', license: null, url: null, attribution: null },
  { group: 'map', providerId: null, name: null, dataKind: 'model', coverage: 'none', status: 'not_configured', license: null, url: null, attribution: null },
];

@Controller('v1')
export class MiscController {
  constructor(
    private readonly locations: LocationsService,
    private readonly db: Db,
    private readonly redis: RedisService,
  ) {}

  @Public()
  @Get('health/live')
  live() {
    return { status: 'ok', version: config.appVersion };
  }

  /** Readiness reflects the database and (when configured) Redis. */
  @Public()
  @Get('health/ready')
  async ready(@Res({ passthrough: true }) res: Response) {
    const [db, redis] = await Promise.all([this.db.ping(), this.redis.ping()]);
    const ok = db && redis !== false;
    if (!ok) res.status(503);
    return { status: ok ? 'ok' : 'unavailable', checks: { database: db, redis: redis === null ? 'not_configured' : redis }, providerMode: config.providerMode };
  }

  @Public()
  @Get('health')
  health() {
    return { status: 'ok', version: config.appVersion, providerMode: config.providerMode };
  }

  @Public()
  @Get('config')
  appConfig(@Query('locale') locale?: string) {
    return {
      schemaVersion: '1.0',
      minAppVersion: '0.1.0',
      locale: locale === 'vi' ? 'vi' : 'en',
      providerMode: config.providerMode,
      features: {
        airQuality: true,
        astronomy: true,
        aurora: { view: true, push: false },
        officialAlerts: false,
        map: false,
        radar: false,
        push: false,
        widgets: false,
        feedback: true,
        aqiStations: false,
      },
      limits: { savedPlacesMax: 20, searchMinChars: 2, searchDebounceMs: 300, refreshCooldownSeconds: 60 },
      legal: {
        privacyUrl: null,
        termsUrl: null,
      },
    };
  }

  @Get('data-sources')
  async dataSources(@Query('locationId') locationId?: string) {
    const loc = locationId ? await this.locations.get(locationId) : null;
    return { schemaVersion: '1.0', generatedAt: toIso(Date.now()), location: loc, providerMode: config.providerMode, sources: SOURCES };
  }

  @Get('alerts')
  alerts(@Query('locationId') locationId?: string) {
    if (!locationId) throw badRequest('locationId', 'validation.required');
    return { status: 'unsupported', reasonCode: 'COVERAGE_NOT_VERIFIED', data: null, cursor: null };
  }

  @Get('maps/manifest')
  mapsManifest() {
    return { status: 'unsupported', reasonCode: 'MAP_PROVIDER_NOT_CONFIGURED', layers: [] };
  }

  /** Text-only feedback (attachments need object storage + scanning — SW078). Idempotent per installation. */
  @Post('feedback')
  @HttpCode(201)
  async feedback(
    @Req() req: AuthedRequest,
    @Headers('idempotency-key') idemKey: string | undefined,
    @Body() body: { type?: string; subject?: string; message?: string; email?: string | null; diagnostics?: Record<string, unknown> | null; consentDiagnostics?: boolean; locale?: string },
  ) {
    if (!idemKey || !/^[A-Za-z0-9-]{8,64}$/.test(idemKey)) throw badRequest('Idempotency-Key', 'validation.idempotencyKey');
    const type = body?.type;
    if (!type || !['bug', 'suggestion', 'other'].includes(type)) throw badRequest('type', 'validation.enum');
    const subject = (body.subject ?? '').trim();
    const message = (body.message ?? '').trim();
    if (subject.length < 5 || subject.length > 120) throw badRequest('subject', 'validation.subjectLength');
    if (message.length < 10 || message.length > 5000) throw badRequest('message', 'validation.messageLength');
    const email = body.email?.trim() || null;
    if (email && (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) throw badRequest('email', 'validation.email');
    const diagnostics = body.consentDiagnostics === true ? sanitizeDiagnostics(body.diagnostics) : null;
    const locale = typeof body.locale === 'string' && /^[a-z]{2}$/.test(body.locale) ? body.locale : null;
    const inst = req.installation!.installationId;
    const hash = createHash('sha256').update(JSON.stringify({ type, subject, message, email })).digest('hex');

    const prior = await this.db.one<{ ticket_id: string; created_at: Date; content_hash: string }>(
      `SELECT ticket_id, created_at, content_hash FROM feedback WHERE installation_id = $1 AND idempotency_key = $2`,
      [inst, idemKey],
    );
    if (prior) {
      if (prior.content_hash !== hash) throw new ApiError(409, 'IDEMPOTENCY_CONFLICT', 'error.idempotencyConflict');
      return { ticketId: prior.ticket_id, status: 'received', receivedAt: toIso(prior.created_at.getTime()), duplicate: true };
    }
    const ticketId = `FB-${randomUUID().slice(0, 8).toUpperCase()}`;
    const row = await this.db.one<{ ticket_id: string; created_at: Date }>(
      `INSERT INTO feedback (ticket_id, installation_id, idempotency_key, content_hash, type, subject, message, email, diagnostics, locale, retain_until)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, now() + interval '180 days')
       ON CONFLICT (installation_id, idempotency_key) DO NOTHING
       RETURNING ticket_id, created_at`,
      [ticketId, inst, idemKey, hash, type, subject, message, email, diagnostics ? JSON.stringify(diagnostics) : null, locale],
    );
    if (!row) {
      // Concurrent retry won the race: return the stored ticket.
      const again = await this.db.one<{ ticket_id: string; created_at: Date }>(`SELECT ticket_id, created_at FROM feedback WHERE installation_id = $1 AND idempotency_key = $2`, [inst, idemKey]);
      return { ticketId: again!.ticket_id, status: 'received', receivedAt: toIso(again!.created_at.getTime()), duplicate: true };
    }
    return { ticketId: row.ticket_id, status: 'received', receivedAt: toIso(row.created_at.getTime()), duplicate: false };
  }
}

/** Keeps only allow-listed, non-identifying diagnostic fields. */
function sanitizeDiagnostics(d: Record<string, unknown> | null | undefined) {
  if (!d || typeof d !== 'object') return null;
  const allowed = ['appVersion', 'buildNumber', 'os', 'osVersion', 'deviceModel', 'locale', 'platform'];
  const out: Record<string, string> = {};
  for (const k of allowed) if (typeof d[k] === 'string') out[k] = String(d[k]).slice(0, 100);
  return out;
}
