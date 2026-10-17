import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import { config } from '../config';

/** Optional Redis connection. `client` is null when REDIS_URL is not set (single-process dev). */
@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly log = new Logger('Redis');
  readonly client: Redis | null;

  constructor() {
    this.client = config.redisUrl ? RedisService.connect(config.redisUrl) : null;
    if (!this.client) this.log.warn('REDIS_URL not set: cache, locks and rate limits are per-process (dev only)');
    this.client?.on('error', (e) => this.log.warn(`redis error: ${e.message}`));
  }

  static connect(url: string): Redis {
    return new Redis(url, { maxRetriesPerRequest: 1, enableOfflineQueue: false, lazyConnect: false });
  }

  async ping(): Promise<boolean | null> {
    if (!this.client) return null;
    try {
      return (await this.client.ping()) === 'PONG';
    } catch {
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.client?.quit().catch(() => undefined);
  }
}
