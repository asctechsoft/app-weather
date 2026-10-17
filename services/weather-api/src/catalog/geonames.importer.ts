import AdmZip from 'adm-zip';
import { createHash, randomUUID } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { Pool } from 'pg';
import { isValidTimezone } from '../common/time';
import { fold, geonamesLocationId, uuidV5 } from '../locations/location.repository';
import { kindOf } from '../locations/locations.service';

/**
 * GeoNames catalog import (SW017, spec §6.1). Steps: download → record URL/date/checksum/license →
 * bounded unzip → parse TSV → validate coordinates, timezone, duplicate IDs → link country/admin1 →
 * aliases (diacritic-folded) → diff against the active dataset → activate in a transaction.
 * Large removals require explicit approval. Locations are never hard-deleted.
 */

export const GEONAMES_LICENSE = 'CC BY 4.0 (GeoNames)';
const MAX_DOWNLOAD_BYTES = 80 * 1024 * 1024;
const MAX_UNZIPPED_BYTES = 400 * 1024 * 1024;
/** Aliases kept per place after folding duplicates: Latin-script first (searchable without
 * diacritics, e.g. "Sài Gòn"), plus a few native-script names (e.g. 東京, Москва). */
const MAX_LATIN_ALIASES = 40;
const MAX_OTHER_ALIASES = 10;
const MAX_ALIASES_PER_PLACE = 2 + MAX_LATIN_ALIASES + MAX_OTHER_ALIASES;
const BATCH = 2000;

export interface GeoNamesRow {
  geonameId: string;
  name: string;
  asciiName: string;
  alternateNames: string[];
  latitude: number;
  longitude: number;
  featureClass: string;
  featureCode: string;
  countryCode: string;
  admin1Code: string;
  admin2Code: string;
  population: number | null;
  timezone: string;
}

export interface ParseReport {
  total: number;
  valid: number;
  rejected: Record<string, number>;
  duplicates: number;
}

export interface ImportOptions {
  dataset: string; // cities500 | cities1000 | cities5000 | cities15000 | <CC> (country file)
  approveLargeChanges?: boolean;
  dryRun?: boolean;
  log?: (m: string) => void;
  /** Local directory containing already-downloaded files (tests / offline). */
  sourceDir?: string;
  baseUrl: string;
  cacheDir: string;
}

export interface ImportResult {
  runId: string;
  report: ParseReport;
  stats: { added: number; updated: number; missingFromNew: number; aliases: number; countries: number; admin1: number };
  activated: boolean;
}

// ---------- download / unzip ----------

/** Downloads with up to 3 attempts (exponential backoff) — GeoNames connections drop occasionally. */
export async function download(url: string, dest: string, attempts = 3): Promise<{ path: string; sha256: string; bytes: number }> {
  for (let i = 1; ; i++) {
    try {
      return await downloadOnce(url, dest);
    } catch (e) {
      if (i >= attempts || /Refusing/.test((e as Error).message)) throw e;
      await new Promise((r) => setTimeout(r, 2000 * 2 ** (i - 1)));
    }
  }
}

async function downloadOnce(url: string, dest: string): Promise<{ path: string; sha256: string; bytes: number }> {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const res = await fetch(url, { headers: { 'User-Agent': 'SkyWeather-Importer/0.1' } });
  if (!res.ok || !res.body) throw new Error(`Download failed ${res.status} for ${url}`);
  const declared = Number(res.headers.get('content-length') ?? 0);
  if (declared > MAX_DOWNLOAD_BYTES) throw new Error(`Refusing ${url}: ${declared} bytes exceeds limit`);
  const hash = createHash('sha256');
  const tmp = `${dest}.part`;
  const out = fs.createWriteStream(tmp);
  let bytes = 0;
  const reader = res.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > MAX_DOWNLOAD_BYTES) {
      out.destroy();
      fs.rmSync(tmp, { force: true });
      throw new Error(`Refusing ${url}: exceeds ${MAX_DOWNLOAD_BYTES} bytes`);
    }
    hash.update(value);
    if (!out.write(value)) await new Promise((r) => out.once('drain', r));
  }
  await new Promise<void>((r, j) => out.end((e?: Error | null) => (e ? j(e) : r())));
  fs.renameSync(tmp, dest);
  return { path: dest, sha256: hash.digest('hex'), bytes };
}

export function sha256File(file: string): string {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

/** Extracts one expected text entry with a hard uncompressed-size limit (zip-bomb guard). */
export function readZipEntry(zipFile: string, entryName: string): string {
  const zip = new AdmZip(zipFile);
  const entries = zip.getEntries();
  if (entries.length > 10) throw new Error(`Unexpected archive layout in ${zipFile}`);
  const entry = entries.find((e) => e.entryName === entryName);
  if (!entry) throw new Error(`${entryName} not found in ${zipFile}`);
  if (entry.header.size > MAX_UNZIPPED_BYTES) throw new Error(`${entryName} is ${entry.header.size} bytes uncompressed — over limit`);
  const data = entry.getData();
  if (data.length > MAX_UNZIPPED_BYTES) throw new Error(`${entryName} exceeded the size limit while extracting`);
  return data.toString('utf8');
}

// ---------- parsing ----------

const LATIN_FOLDED = /^[a-z0-9 .'’()-]+$/;

/** Unique (by folded form) alternate names, bounded per script, excluding codes/URLs. */
export function selectAlternates(name: string, ascii: string, raw: string): string[] {
  if (!raw) return [];
  const seen = new Set([fold(name), fold(ascii)]);
  const latin: string[] = [];
  const other: string[] = [];
  for (const a of raw.split(',')) {
    const s = a.trim();
    // Skip codes such as IATA/abbreviations ("NOI", "SGN"): they only add noisy fuzzy matches.
    if (s.length < 2 || s.length > 100 || ALIAS_NOISE.test(s) || /^[A-Z]{2,4}$/.test(s)) continue;
    const f = fold(s);
    if (!f || seen.has(f)) continue;
    seen.add(f);
    if (LATIN_FOLDED.test(f)) {
      if (latin.length < MAX_LATIN_ALIASES) latin.push(s);
    } else if (other.length < MAX_OTHER_ALIASES) {
      other.push(s);
    }
    if (latin.length >= MAX_LATIN_ALIASES && other.length >= MAX_OTHER_ALIASES) break;
  }
  return [...latin, ...other];
}

const ALIAS_NOISE = /(https?:|www\.|\d|\/)/i;

export function parseCities(tsv: string): { rows: GeoNamesRow[]; report: ParseReport } {
  const report: ParseReport = { total: 0, valid: 0, rejected: {}, duplicates: 0 };
  const reject = (why: string) => (report.rejected[why] = (report.rejected[why] ?? 0) + 1);
  const seen = new Set<string>();
  const rows: GeoNamesRow[] = [];
  for (const line of tsv.split('\n')) {
    if (!line.trim()) continue;
    report.total++;
    const c = line.replace(/\r$/, '').split('\t');
    if (c.length < 19) {
      reject('column_count');
      continue;
    }
    const [id, name, ascii, alt, lat, lon, fclass, fcode, cc, , a1, a2, , , pop, , , tz] = c;
    const latitude = Number(lat);
    const longitude = Number(lon);
    if (!/^\d+$/.test(id)) {
      reject('bad_id');
      continue;
    }
    if (seen.has(id)) {
      report.duplicates++;
      continue;
    }
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
      reject('bad_coordinate');
      continue;
    }
    if (!tz || !isValidTimezone(tz)) {
      reject('bad_timezone');
      continue;
    }
    if (!name.trim() || !/^[A-Z]{2}$/.test(cc)) {
      reject('missing_name_or_country');
      continue;
    }
    if (fclass !== 'P' && fclass !== 'A') {
      reject('feature_class');
      continue;
    }
    seen.add(id);
    const alternates = selectAlternates(name, ascii, alt);
    rows.push({
      geonameId: id,
      name: name.trim(),
      asciiName: ascii.trim(),
      alternateNames: alternates,
      latitude,
      longitude,
      featureClass: fclass,
      featureCode: fcode,
      countryCode: cc,
      admin1Code: a1,
      admin2Code: a2,
      population: pop && /^\d+$/.test(pop) && pop !== '0' ? Number(pop) : null,
      timezone: tz,
    });
    report.valid++;
  }
  return { rows, report };
}

export function parseAdmin1(tsv: string): Map<string, { name: string; ascii: string; geonameId: string }> {
  const m = new Map<string, { name: string; ascii: string; geonameId: string }>();
  for (const line of tsv.split('\n')) {
    const c = line.replace(/\r$/, '').split('\t');
    if (c.length < 4 || !c[0].includes('.')) continue;
    m.set(c[0], { name: c[1], ascii: c[2], geonameId: c[3] });
  }
  return m;
}

export function parseCountries(tsv: string): Map<string, { name: string; iso3: string; continent: string }> {
  const m = new Map<string, { name: string; iso3: string; continent: string }>();
  for (const line of tsv.split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue;
    const c = line.replace(/\r$/, '').split('\t');
    if (c.length < 9 || !/^[A-Z]{2}$/.test(c[0])) continue;
    m.set(c[0], { name: c[4], iso3: c[1], continent: c[8] });
  }
  return m;
}

/** Unique folded aliases: preferred name, ASCII name, then alternates (bounded). */
export function aliasesFor(r: GeoNamesRow): { alias: string; folded: string; preferred: boolean }[] {
  const out: { alias: string; folded: string; preferred: boolean }[] = [];
  const seen = new Set<string>();
  const add = (alias: string, preferred: boolean) => {
    const f = fold(alias);
    if (!f || seen.has(f) || out.length >= MAX_ALIASES_PER_PLACE) return;
    seen.add(f);
    out.push({ alias, folded: f, preferred });
  };
  add(r.name, true);
  add(r.asciiName, false);
  for (const a of r.alternateNames) add(a, false);
  return out;
}

// ---------- import ----------

export async function importGeoNames(pool: Pool, opts: ImportOptions): Promise<ImportResult> {
  const log = opts.log ?? (() => undefined);
  const zipName = `${opts.dataset}.zip`;
  const files = { cities: zipName, admin1: 'admin1CodesASCII.txt', countries: 'countryInfo.txt' };
  const dir = opts.sourceDir ?? opts.cacheDir;
  const local = (f: string) => path.join(dir, f);
  const meta: Record<string, { sha256: string; url: string | null }> = {};

  for (const f of Object.values(files)) {
    if (opts.sourceDir) {
      meta[f] = { sha256: sha256File(local(f)), url: null };
    } else {
      const url = `${opts.baseUrl}/${f}`;
      log(`downloading ${url}`);
      const d = await download(url, local(f));
      meta[f] = { sha256: d.sha256, url };
    }
  }

  const { rows, report } = parseCities(readZipEntry(local(files.cities), `${opts.dataset}.txt`));
  const admin1 = parseAdmin1(fs.readFileSync(local(files.admin1), 'utf8'));
  const countries = parseCountries(fs.readFileSync(local(files.countries), 'utf8'));
  log(`parsed ${report.valid}/${report.total} rows (${report.duplicates} duplicates, rejected ${JSON.stringify(report.rejected)})`);
  if (report.valid === 0) throw new Error('No valid rows — refusing to import');

  // One import at a time. Any run still "running" while we hold the lock was interrupted (crash).
  const lockClient = await pool.connect();
  const locked = (await lockClient.query<{ ok: boolean }>('SELECT pg_try_advisory_lock($1) AS ok', [727_201])).rows[0].ok;
  if (!locked) {
    lockClient.release();
    throw new Error('Another GeoNames import is running');
  }
  try {
    await pool.query(
      `UPDATE ingestion_runs SET status = 'failed', finished_at = now(), stats = stats || '{"error":"interrupted"}'::jsonb
        WHERE source = 'geonames' AND status = 'running'`,
    );
    return await runImport(pool, opts, rows, report, meta, files, admin1, countries, log);
  } finally {
    await lockClient.query('SELECT pg_advisory_unlock($1)', [727_201]).catch(() => undefined);
    lockClient.release();
  }
}

async function runImport(
  pool: Pool,
  opts: ImportOptions,
  rows: GeoNamesRow[],
  report: ParseReport,
  meta: Record<string, { sha256: string; url: string | null }>,
  files: { cities: string; admin1: string; countries: string },
  admin1: Map<string, { name: string; ascii: string; geonameId: string }>,
  countries: Map<string, { name: string; iso3: string; continent: string }>,
  log: (m: string) => void,
): Promise<ImportResult> {
  const runId = randomUUID();
  await pool.query(
    `INSERT INTO ingestion_runs (id, source, dataset, url, checksum_sha256, license, stats) VALUES ($1,'geonames',$2,$3,$4,$5,$6)`,
    [runId, opts.dataset, meta[files.cities].url, meta[files.cities].sha256, GEONAMES_LICENSE, JSON.stringify({ parse: report, files: meta })],
  );

  const stats = { added: 0, updated: 0, missingFromNew: 0, aliases: 0, countries: 0, admin1: 0 };
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Countries + admin1 (provider codes, not legal codes).
    for (const [code, c] of countries) {
      await client.query(
        `INSERT INTO countries (code, name, iso3, continent, updated_run_id) VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, iso3 = EXCLUDED.iso3, continent = EXCLUDED.continent, updated_run_id = EXCLUDED.updated_run_id`,
        [code, c.name, c.iso3 || null, c.continent || null, runId],
      );
      stats.countries++;
    }
    const admin1Ids = new Map<string, string>();
    for (const [code, a] of admin1) {
      const id = uuidV5(`geonames-admin1:${code}`);
      admin1Ids.set(code, id);
      await client.query(
        `INSERT INTO admin_units (id, country_code, level, provider, provider_code, name, name_ascii, updated_run_id)
         VALUES ($1,$2,'admin1','geonames',$3,$4,$5,$6)
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, name_ascii = EXCLUDED.name_ascii, updated_run_id = EXCLUDED.updated_run_id`,
        [id, code.slice(0, 2), code, a.name, a.ascii, runId],
      );
      stats.admin1++;
    }

    const existing = new Set(
      (await client.query<{ external_id: string }>(`SELECT external_id FROM location_external_ids WHERE provider = 'geonames'`)).rows.map((r) => r.external_id),
    );
    const previousCatalog = Number(
      (await client.query<{ n: string }>(`SELECT count(*) AS n FROM locations WHERE in_catalog AND retired_at IS NULL`)).rows[0].n,
    );

    for (let i = 0; i < rows.length; i += BATCH) {
      const batch = rows.slice(i, i + BATCH);
      const ids = batch.map((r) => geonamesLocationId(r.geonameId));
      for (const r of batch) (existing.has(r.geonameId) ? stats.updated++ : stats.added++);
      // Existing rows keep their coordinate (saved places must not move); labels are refreshed.
      await client.query(
        `INSERT INTO locations (location_id, kind, name, country_code, admin1_name, latitude, longitude, timezone,
                                coordinate_source, feature_code, population, in_catalog, updated_run_id)
         SELECT * FROM unnest($1::uuid[], $2::text[], $3::text[], $4::char(2)[], $5::text[], $6::float8[], $7::float8[],
                              $8::text[], $9::text[], $10::text[], $11::bigint[], $12::bool[], $13::uuid[])
         ON CONFLICT (location_id) DO UPDATE SET
           name = EXCLUDED.name, admin1_name = EXCLUDED.admin1_name, feature_code = EXCLUDED.feature_code,
           population = EXCLUDED.population, in_catalog = true, updated_run_id = EXCLUDED.updated_run_id,
           retired_at = NULL, updated_at = now()`,
        [
          ids,
          batch.map((r) => kindOf(r.featureCode)),
          batch.map((r) => r.name),
          batch.map((r) => r.countryCode),
          batch.map((r) => admin1.get(`${r.countryCode}.${r.admin1Code}`)?.name ?? null),
          batch.map((r) => r.latitude),
          batch.map((r) => r.longitude),
          batch.map((r) => r.timezone),
          batch.map(() => 'catalog'),
          batch.map((r) => r.featureCode),
          batch.map((r) => r.population),
          batch.map(() => true),
          batch.map(() => runId),
        ],
      );
      await client.query(
        `INSERT INTO location_external_ids (provider, external_id, location_id)
         SELECT 'geonames', * FROM unnest($1::text[], $2::uuid[]) ON CONFLICT DO NOTHING`,
        [batch.map((r) => r.geonameId), ids],
      );
      const links = batch
        .map((r, k) => ({ loc: ids[k], admin: admin1Ids.get(`${r.countryCode}.${r.admin1Code}`) }))
        .filter((x): x is { loc: string; admin: string } => !!x.admin);
      if (links.length) {
        await client.query(
          `INSERT INTO location_admin_links (location_id, admin_unit_id, source, version)
           SELECT l, a, 'geonames', $3 FROM unnest($1::uuid[], $2::uuid[]) AS t(l, a) ON CONFLICT DO NOTHING`,
          [links.map((x) => x.loc), links.map((x) => x.admin), opts.dataset],
        );
      }
      const al = batch.flatMap((r, k) => aliasesFor(r).map((a) => ({ id: ids[k], ...a })));
      stats.aliases += al.length;
      await client.query(
        `INSERT INTO location_aliases (location_id, locale, alias, alias_folded, is_preferred)
         SELECT l, 'und', a, f, p FROM unnest($1::uuid[], $2::text[], $3::text[], $4::bool[]) AS t(l, a, f, p)
         ON CONFLICT DO NOTHING`,
        [al.map((a) => a.id), al.map((a) => a.alias), al.map((a) => a.folded), al.map((a) => a.preferred)],
      );
      log(`  ${Math.min(i + BATCH, rows.length)}/${rows.length}`);
    }

    // Catalog places absent from the new dataset: reported for review, never deleted.
    // Every row of this dataset was stamped with runId above, so "missing" = catalog rows not stamped.
    stats.missingFromNew = Number(
      (
        await client.query<{ n: string }>(
          `SELECT count(*) AS n FROM locations WHERE in_catalog AND retired_at IS NULL AND updated_run_id IS DISTINCT FROM $1`,
          [runId],
        )
      ).rows[0].n,
    );
    const removalShare = previousCatalog ? stats.missingFromNew / previousCatalog : 0;
    const large = removalShare > 0.05;
    if (large && !opts.approveLargeChanges) {
      throw new Error(`Large change: ${stats.missingFromNew} of ${previousCatalog} catalog places missing (${(removalShare * 100).toFixed(1)}%). Re-run with --approve-large-changes after review.`);
    }
    if (opts.dryRun) throw new DryRun();

    await client.query(`UPDATE ingestion_runs SET is_active = false WHERE source = 'geonames' AND dataset = $1 AND is_active`, [opts.dataset]);
    await client.query(
      `UPDATE ingestion_runs SET status = 'succeeded', is_active = true, finished_at = now(), stats = stats || $2::jsonb WHERE id = $1`,
      [runId, JSON.stringify({ diff: stats })],
    );
    await client.query('COMMIT');
    log(`activated run ${runId}: ${JSON.stringify(stats)}`);
    return { runId, report, stats, activated: true };
  } catch (e) {
    await client.query('ROLLBACK').catch(() => undefined);
    const dry = e instanceof DryRun;
    await pool.query(`UPDATE ingestion_runs SET status = $2, finished_at = now(), stats = stats || $3::jsonb WHERE id = $1`, [
      runId,
      dry ? 'rolled_back' : 'failed',
      JSON.stringify({ diff: stats, error: dry ? 'dry_run' : (e as Error).message }),
    ]);
    if (dry) return { runId, report, stats, activated: false };
    throw e;
  } finally {
    client.release();
  }
}

class DryRun extends Error {}
