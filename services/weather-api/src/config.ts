import * as fs from 'fs';
import * as path from 'path';

/** Loads `.env` (if present) without overriding real environment variables. */
function loadDotEnv(): void {
  const file = path.resolve(process.cwd(), '.env');
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
  }
}

loadDotEnv();

function str(name: string, fallback: string): string {
  const v = process.env[name];
  return v === undefined || v === '' ? fallback : v;
}

function int(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const v = Number(raw);
  if (!Number.isInteger(v) || v <= 0) throw new Error(`Invalid integer env ${name}`);
  return v;
}

const mode = str('PROVIDER_MODE', 'live');
if (mode !== 'live' && mode !== 'fixture') throw new Error('PROVIDER_MODE must be live or fixture');

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env ${name} (see .env.example)`);
  return v;
}

export const config = {
  port: int('PORT', 8080),
  /** Required: fail at boot rather than at the first request (SW007). */
  get databaseUrl(): string {
    return required('DATABASE_URL');
  },
  dbPoolMax: int('DB_POOL_MAX', 10),
  /** Optional: without it the cache is per-process memory (dev only). */
  redisUrl: str('REDIS_URL', ''),
  installationTokenTtlDays: int('INSTALLATION_TOKEN_TTL_DAYS', 90),
  /** Requests per minute per installation (429 + Retry-After above it). */
  rateLimitPerMinute: int('RATE_LIMIT_PER_MINUTE', 120),
  geonamesCacheDir: path.resolve(str('GEONAMES_CACHE_DIR', './.geonames')),
  geonamesBaseUrl: str('GEONAMES_BASE_URL', 'https://download.geonames.org/export/dump'),
  corsOrigins: str('CORS_ORIGINS', '*'),
  dataDir: path.resolve(str('DATA_DIR', './data')),
  providerMode: mode as 'live' | 'fixture',
  fixtureDir: path.resolve(__dirname, '../../../packages/contracts/fixtures'),
  openMeteo: {
    forecastHost: str('OPEN_METEO_FORECAST_HOST', 'https://api.open-meteo.com'),
    aqHost: str('OPEN_METEO_AQ_HOST', 'https://air-quality-api.open-meteo.com'),
    geocodingHost: str('OPEN_METEO_GEOCODING_HOST', 'https://geocoding-api.open-meteo.com'),
    apiKey: str('OPEN_METEO_API_KEY', ''),
  },
  noaaHost: str('NOAA_SWPC_HOST', 'https://services.swpc.noaa.gov'),
  providerTimeoutMs: int('PROVIDER_TIMEOUT_MS', 3000),
  appVersion: '0.1.0',
};
