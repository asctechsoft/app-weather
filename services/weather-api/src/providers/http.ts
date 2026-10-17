import { config } from '../config';

export class ProviderError extends Error {
  constructor(
    readonly providerId: string,
    readonly reasonCode: 'TIMEOUT' | 'HTTP_ERROR' | 'RATE_LIMITED' | 'MALFORMED' | 'NETWORK' | 'CIRCUIT_OPEN',
    readonly httpStatus?: number,
  ) {
    // Never include the request URL: it may carry an API key.
    super(`${providerId}: ${reasonCode}${httpStatus ? ` (${httpStatus})` : ''}`);
  }
}

const SECRET_PARAMS = /([?&](?:apikey|key|appid)=)[^&]+/gi;

export function redactUrl(url: string): string {
  return url.replace(SECRET_PARAMS, '$1***');
}

/**
 * Per-provider circuit breaker: after 5 consecutive upstream failures the provider is
 * skipped for 30 s (callers fall back to stale cache) instead of piling up timeouts.
 * Client errors (4xx except 429) do not count: retrying cannot fix them.
 */
const breakers = new Map<string, { failures: number; openUntil: number }>();
const BREAKER_THRESHOLD = 5;
const BREAKER_OPEN_MS = 30_000;

export function breakerState(providerId: string) {
  return breakers.get(providerId) ?? { failures: 0, openUntil: 0 };
}

export function resetBreakers(): void {
  breakers.clear();
}

function recordResult(providerId: string, ok: boolean, now = Date.now()): void {
  const b = breakerState(providerId);
  if (ok) {
    breakers.set(providerId, { failures: 0, openUntil: 0 });
    return;
  }
  const failures = b.failures + 1;
  breakers.set(providerId, { failures, openUntil: failures >= BREAKER_THRESHOLD ? now + BREAKER_OPEN_MS : b.openUntil });
}

export async function fetchJson<T>(providerId: string, url: string, timeoutMs = config.providerTimeoutMs): Promise<T> {
  if (breakerState(providerId).openUntil > Date.now()) throw new ProviderError(providerId, 'CIRCUIT_OPEN');
  try {
    const out = await fetchJsonOnce<T>(providerId, url, timeoutMs);
    recordResult(providerId, true);
    return out;
  } catch (e) {
    const clientError = e instanceof ProviderError && e.reasonCode === 'HTTP_ERROR' && (e.httpStatus ?? 0) < 500;
    if (!clientError) recordResult(providerId, false);
    throw e;
  }
}

async function fetchJsonOnce<T>(providerId: string, url: string, timeoutMs: number): Promise<T> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let res: Response;
  try {
    res = await fetch(url, { signal: ctrl.signal, headers: { 'User-Agent': 'SkyWeather-WeatherServer/0.1' } });
  } catch (e) {
    throw new ProviderError(providerId, (e as Error).name === 'AbortError' ? 'TIMEOUT' : 'NETWORK');
  } finally {
    clearTimeout(timer);
  }
  if (res.status === 429) throw new ProviderError(providerId, 'RATE_LIMITED', 429);
  if (!res.ok) throw new ProviderError(providerId, 'HTTP_ERROR', res.status);
  try {
    return (await res.json()) as T;
  } catch {
    throw new ProviderError(providerId, 'MALFORMED');
  }
}
