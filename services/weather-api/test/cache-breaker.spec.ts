import RedisMock from 'ioredis-mock';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { RedisTtlCache } from '../src/common/cache';
import { breakerState, fetchJson, ProviderError, resetBreakers } from '../src/providers/http';

describe('RedisTtlCache (SW025)', () => {
  it('shares one upstream load across instances via the Redis lock', async () => {
    const redis = new RedisMock();
    const a = new RedisTtlCache(redis as never);
    const b = new RedisTtlCache(redis as never);
    let calls = 0;
    const load = () => new Promise<number>((r) => setTimeout(() => r(++calls), 150));
    const results = await Promise.all([a.getOrLoad('k', 60_000, 120_000, load), b.getOrLoad('k', 60_000, 120_000, load)]);
    expect(calls).toBe(1);
    expect(results.map((r) => r.value)).toEqual([1, 1]);
  });

  it('serves stale data when the refresh fails within the stale cap', async () => {
    const redis = new RedisMock();
    let now = 1_000_000;
    const cache = new RedisTtlCache(redis as never, () => now);
    await cache.getOrLoad('stale-k', 100, 10_000, async () => 'v1');
    now += 500;
    const r = await cache.getOrLoad('stale-k', 100, 10_000, async () => {
      throw new Error('down');
    });
    expect(r).toMatchObject({ value: 'v1', stale: true });
  });
});

describe('circuit breaker', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    resetBreakers();
  });

  it('opens after 5 consecutive upstream failures and stops calling the provider', async () => {
    const fetchMock = vi.fn(async () => new Response('{}', { status: 503 }));
    vi.stubGlobal('fetch', fetchMock);
    for (let i = 0; i < 5; i++) await expect(fetchJson('p', 'https://x.invalid')).rejects.toBeInstanceOf(ProviderError);
    expect(breakerState('p').openUntil).toBeGreaterThan(Date.now());
    await expect(fetchJson('p', 'https://x.invalid')).rejects.toMatchObject({ reasonCode: 'CIRCUIT_OPEN' });
    expect(fetchMock).toHaveBeenCalledTimes(5);
  });

  it('does not count client errors (400) as provider failures', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 400 })));
    for (let i = 0; i < 6; i++) await expect(fetchJson('q', 'https://x.invalid')).rejects.toBeInstanceOf(ProviderError);
    expect(breakerState('q').openUntil).toBe(0);
  });
});
