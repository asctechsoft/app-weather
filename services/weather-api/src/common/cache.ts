import type Redis from 'ioredis';

/**
 * TTL cache with single-flight and a stale cap (spec §10.4).
 * - fresh: age < ttl → served directly.
 * - stale: ttl <= age < staleCap → served only when the upstream refresh fails.
 * `TtlCache` is per-process; `RedisTtlCache` shares entries and a load lock across
 * API and worker instances. Both expose the same `getOrLoad`.
 */
export interface CacheEntry<T> {
  value: T;
  storedAt: number;
}

export interface CacheResult<T> {
  value: T;
  storedAt: number;
  stale: boolean;
}

export interface Cache {
  getOrLoad<T>(key: string, ttlMs: number, staleCapMs: number, load: () => Promise<T>, opts?: { forceRefresh?: boolean }): Promise<CacheResult<T>>;
}

export class TtlCache implements Cache {
  private readonly entries = new Map<string, CacheEntry<unknown>>();
  private readonly inflight = new Map<string, Promise<unknown>>();

  constructor(private readonly now: () => number = Date.now) {}

  async getOrLoad<T>(
    key: string,
    ttlMs: number,
    staleCapMs: number,
    load: () => Promise<T>,
    opts: { forceRefresh?: boolean } = {},
  ): Promise<CacheResult<T>> {
    const entry = this.entries.get(key) as CacheEntry<T> | undefined;
    const age = entry ? this.now() - entry.storedAt : Infinity;
    if (entry && age < ttlMs && !opts.forceRefresh) {
      return { value: entry.value, storedAt: entry.storedAt, stale: false };
    }
    try {
      const value = await this.singleFlight(key, load);
      const stored = this.entries.get(key) as CacheEntry<T>;
      return { value, storedAt: stored.storedAt, stale: false };
    } catch (err) {
      if (entry && age < staleCapMs) {
        return { value: entry.value, storedAt: entry.storedAt, stale: true };
      }
      throw err;
    }
  }

  peek<T>(key: string): CacheEntry<T> | undefined {
    return this.entries.get(key) as CacheEntry<T> | undefined;
  }

  private singleFlight<T>(key: string, load: () => Promise<T>): Promise<T> {
    const pending = this.inflight.get(key) as Promise<T> | undefined;
    if (pending) return pending;
    const p = load()
      .then((value) => {
        this.entries.set(key, { value, storedAt: this.now() });
        return value;
      })
      .finally(() => this.inflight.delete(key));
    this.inflight.set(key, p);
    return p;
  }
}

/**
 * Redis-backed cache. A `SET NX PX` lock makes one instance load a missing key while the
 * others wait briefly (then fall back to stale data, or load themselves if Redis is down).
 */
export class RedisTtlCache implements Cache {
  private readonly inflight = new Map<string, Promise<CacheResult<unknown>>>();

  constructor(
    private readonly redis: Redis,
    private readonly now: () => number = Date.now,
    private readonly lockMs = 10_000,
    private readonly waitMs = 3_000,
  ) {}

  getOrLoad<T>(key: string, ttlMs: number, staleCapMs: number, load: () => Promise<T>, opts: { forceRefresh?: boolean } = {}): Promise<CacheResult<T>> {
    const pending = this.inflight.get(key);
    if (pending && !opts.forceRefresh) return pending as Promise<CacheResult<T>>;
    const p = this.run(key, ttlMs, staleCapMs, load, opts).finally(() => this.inflight.delete(key));
    this.inflight.set(key, p);
    return p;
  }

  private async read<T>(key: string): Promise<CacheEntry<T> | null> {
    try {
      const raw = await this.redis.get(`c:${key}`);
      return raw ? (JSON.parse(raw) as CacheEntry<T>) : null;
    } catch {
      return null;
    }
  }

  private async run<T>(key: string, ttlMs: number, staleCapMs: number, load: () => Promise<T>, opts: { forceRefresh?: boolean }): Promise<CacheResult<T>> {
    let entry = await this.read<T>(key);
    const fresh = (e: CacheEntry<T> | null) => !!e && this.now() - e.storedAt < ttlMs;
    if (fresh(entry) && !opts.forceRefresh) return { value: entry!.value, storedAt: entry!.storedAt, stale: false };

    let locked = true;
    try {
      locked = (await this.redis.set(`lock:${key}`, '1', 'PX', this.lockMs, 'NX')) === 'OK';
    } catch {
      locked = true; // Redis unavailable: load directly.
    }

    if (!locked) {
      const deadline = this.now() + this.waitMs;
      while (this.now() < deadline) {
        await new Promise((r) => setTimeout(r, 100));
        const e = await this.read<T>(key);
        if (e && (!entry || e.storedAt > entry.storedAt)) return { value: e.value, storedAt: e.storedAt, stale: false };
      }
      entry = await this.read<T>(key);
      if (entry && this.now() - entry.storedAt < staleCapMs) return { value: entry.value, storedAt: entry.storedAt, stale: !fresh(entry) };
    }

    try {
      const value = await load();
      const stored: CacheEntry<T> = { value, storedAt: this.now() };
      await this.redis.set(`c:${key}`, JSON.stringify(stored), 'PX', staleCapMs).catch(() => undefined);
      return { value, storedAt: stored.storedAt, stale: false };
    } catch (err) {
      if (entry && this.now() - entry.storedAt < staleCapMs) return { value: entry.value, storedAt: entry.storedAt, stale: true };
      throw err;
    } finally {
      if (locked) await this.redis.del(`lock:${key}`).catch(() => undefined);
    }
  }
}
