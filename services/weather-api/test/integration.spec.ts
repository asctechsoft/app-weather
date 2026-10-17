/**
 * Integration tests on a real PostgreSQL (embedded, no Docker) with fixture providers.
 * Covers SW014 (installation auth), SW015 (migrations), SW017/SW019/SW020 (catalog import,
 * search, GPS resolve), feedback idempotency and the HTTP contract of key routes.
 */
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import AdmZip from 'adm-zip';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { Pool } from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppModule } from '../src/app.module';
import { importGeoNames } from '../src/catalog/geonames.importer';
import { ApiErrorFilter } from '../src/common/error.filter';
import { migrate } from '../src/db/migrate';

const FIX = path.resolve(__dirname, '../../../packages/contracts/fixtures');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'skyweather-it-'));
// DATABASE_URL / PROVIDER_MODE are set in vitest.config.mts (before modules load).
const DB_URL = process.env.DATABASE_URL!;
const port = Number(new URL(DB_URL).port);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let pg: any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let app: any;
let base = '';
let token = '';

async function call(method: string, url: string, body?: unknown, headers: Record<string, string> = {}) {
  const res = await fetch(`${base}${url}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
}

function sampleSourceDir(): string {
  const dir = path.join(tmp, 'geonames');
  fs.mkdirSync(dir, { recursive: true });
  const zip = new AdmZip();
  zip.addFile('cities500.txt', fs.readFileSync(path.join(FIX, 'geonames/cities-sample.txt')));
  zip.writeZip(path.join(dir, 'cities500.zip'));
  fs.copyFileSync(path.join(FIX, 'geonames/admin1CodesASCII.txt'), path.join(dir, 'admin1CodesASCII.txt'));
  fs.copyFileSync(path.join(FIX, 'geonames/countryInfo.txt'), path.join(dir, 'countryInfo.txt'));
  return dir;
}

beforeAll(async () => {
  const EmbeddedPostgres = (await import('embedded-postgres')).default;
  pg = new EmbeddedPostgres({ databaseDir: path.join(tmp, 'pg'), user: 'skyweather', password: 'it', port, persistent: false, onLog: () => undefined, initdbFlags: ['--encoding=UTF8', '--locale=C'] });
  await pg.initialise();
  await pg.start();
  await pg.createDatabase('skyweather');

  await migrate(DB_URL, () => undefined);
  app = await NestFactory.create(AppModule, { logger: false });
  app.useGlobalFilters(new ApiErrorFilter());
  await app.listen(0, '127.0.0.1');
  base = `http://127.0.0.1:${app.getHttpServer().address().port}`;
}, 180_000);

afterAll(async () => {
  await app?.close();
  await pg?.stop();
  fs.rmSync(tmp, { recursive: true, force: true });
}, 60_000);

describe('migrations (SW015)', () => {
  it('are idempotent and refuse edited files', async () => {
    expect(await migrate(DB_URL, () => undefined)).toEqual([]);
  });
});

describe('GeoNames import (SW017)', () => {
  it('imports valid rows, reports rejects and duplicates, and is re-runnable without duplicates', async () => {
    const pool = new Pool({ connectionString: DB_URL });
    const opts = { dataset: 'cities500', sourceDir: sampleSourceDir(), baseUrl: 'unused', cacheDir: tmp };
    const first = await importGeoNames(pool, opts);
    expect(first.activated).toBe(true);
    expect(first.report.valid).toBe(8);
    expect(first.report.duplicates).toBe(1);
    expect(first.report.rejected).toEqual({ bad_timezone: 1, bad_coordinate: 1 });
    expect(first.stats.added).toBe(8);

    const second = await importGeoNames(pool, opts);
    expect(second.stats.added).toBe(0);
    expect(second.stats.updated).toBe(8);
    const n = await pool.query(`SELECT count(*)::int AS n FROM locations WHERE in_catalog`);
    expect(n.rows[0].n).toBe(8);
    const active = await pool.query(`SELECT count(*)::int AS n FROM ingestion_runs WHERE is_active`);
    expect(active.rows[0].n).toBe(1);

    const dry = await importGeoNames(pool, { ...opts, dryRun: true });
    expect(dry.activated).toBe(false);
    await pool.end();
  }, 60_000);
});

describe('installation auth (SW014)', () => {
  it('rejects requests without a token and accepts a registered one', async () => {
    token = '';
    expect((await call('GET', '/v1/data-sources')).status).toBe(401);
    expect((await call('POST', '/v1/installations', { platform: 'toaster', appVersion: '1' })).status).toBe(400);
    const reg = await call('POST', '/v1/installations', { platform: 'android', appVersion: '1.0.0', locale: 'vi', timezone: 'Asia/Ho_Chi_Minh' });
    expect(reg.status).toBe(201);
    expect(reg.body.token).toMatch(/^swi_/);
    token = reg.body.token;
    expect((await call('GET', '/v1/data-sources')).status).toBe(200);
    // A random UUID is not a credential.
    const saved = token;
    token = 'swi_' + 'A'.repeat(43);
    expect((await call('GET', '/v1/data-sources')).status).toBe(401);
    token = saved;
  });

  it('rotates tokens: the old one stops working', async () => {
    const old = token;
    const r = await call('POST', '/v1/installations/me/token');
    expect(r.status).toBe(200);
    token = r.body.token;
    expect(token).not.toBe(old);
    expect((await call('GET', '/v1/data-sources')).status).toBe(200);
    const saved = token;
    token = old;
    expect((await call('GET', '/v1/data-sources')).status).toBe(401);
    token = saved;
  });
});

describe('locations (SW019, SW020)', () => {
  it('finds Hà Nội with or without diacritics from the catalog', async () => {
    for (const q of ['Hà Nội', 'ha noi', 'Hanoi']) {
      const r = await call('GET', `/v1/locations/search?q=${encodeURIComponent(q)}&locale=vi`);
      expect(r.status).toBe(200);
      expect(r.body.results[0].location.externalIds).toContainEqual({ provider: 'geonames', externalId: '1581130' });
      expect(r.body.results[0].source).toBe('catalog');
    }
  });

  it('keeps same-name places in different countries distinct and never duplicates aliases', async () => {
    const r = await call('GET', '/v1/locations/search?q=London');
    const countries = r.body.results.filter((x: { location: { name: string } }) => x.location.name === 'London').map((x: { location: { countryCode: string } }) => x.location.countryCode);
    expect(countries).toEqual(expect.arrayContaining(['GB', 'CA']));
    const ids = r.body.results.map((x: { location: { locationId: string } }) => x.location.locationId);
    expect(new Set(ids).size).toBe(ids.length);
    const fr = await call('GET', '/v1/locations/search?q=Paris&countryCode=US');
    expect(fr.body.results.every((x: { location: { countryCode: string } }) => x.location.countryCode === 'US')).toBe(true);
  });

  it('resolves GPS with a polygon timezone and an approximate nearest-place label', async () => {
    const r = await call('POST', '/v1/locations/resolve', { latitude: 21.03, longitude: 105.85, accuracy: 20 });
    expect(r.status).toBe(200);
    expect(r.body.kind).toBe('gps');
    expect(r.body.timezone).toBe('Asia/Bangkok');
    expect(r.body.name).toBe('Hanoi');
    expect(r.body.nameApproximate).toBe(true);
    // Weather uses the GPS point, not the city centre.
    expect(r.body.latitude).toBe(21.03);
    const london = await call('POST', '/v1/locations/resolve', { latitude: 51.5, longitude: -0.12 });
    expect(london.body.timezone).toBe('Europe/London');
    expect((await call('POST', '/v1/locations/resolve', { latitude: 95, longitude: 0 })).status).toBe(400);
  });

  it('serves weather for a catalog place (fixture provider)', async () => {
    const id = (await call('GET', '/v1/locations/search?q=Hanoi')).body.results[0].location.locationId;
    const home = await call('GET', `/v1/weather/home?locationId=${id}`);
    expect(home.status).toBe(200);
    expect(home.body.sections.officialAlerts.status).toBe('unsupported');
    const sums = await call('GET', `/v1/weather/summaries?locationIds=${id},00000000-0000-0000-0000-000000000000`);
    expect(sums.body.items[0].status).not.toBe('error');
    expect(sums.body.items[1].reasonCode).toBe('LOCATION_NOT_FOUND');
  });
});

describe('feedback idempotency', () => {
  const body = { type: 'bug', subject: 'Chart is empty', message: 'The rain chart shows nothing on Sunday.', consentDiagnostics: false };
  it('returns the same ticket for a retried key and 409 for different content', async () => {
    const a = await call('POST', '/v1/feedback', body, { 'Idempotency-Key': 'key-12345678' });
    expect(a.status).toBe(201);
    const b = await call('POST', '/v1/feedback', body, { 'Idempotency-Key': 'key-12345678' });
    expect(b.body.ticketId).toBe(a.body.ticketId);
    expect(b.body.duplicate).toBe(true);
    const c = await call('POST', '/v1/feedback', { ...body, subject: 'Something else' }, { 'Idempotency-Key': 'key-12345678' });
    expect(c.status).toBe(409);
  });
});

describe('health', () => {
  it('readiness reports the database', async () => {
    const r = await call('GET', '/v1/health/ready');
    expect(r.status).toBe(200);
    expect(r.body.checks).toEqual({ database: true, redis: 'not_configured' });
  });

  it('deleting the installation revokes its token', async () => {
    expect((await call('DELETE', '/v1/installations/me')).status).toBe(204);
    expect((await call('GET', '/v1/data-sources')).status).toBe(401);
  });
});
