import 'reflect-metadata';
import { Logger, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { CORE_PROVIDERS } from './app.module';
import { config } from './config';
import { RedisService } from './common/redis';
import { Db } from './db/db';
import { LocationRepository } from './locations/location.repository';
import { SnapshotService } from './weather/snapshot.service';

/**
 * Background worker (SW007): same codebase as the API, separate process/container
 * (`npm run worker`). Jobs warm the shared Redis cache so foreground requests stay fast:
 * - NOAA Kp: fetched once for everyone (never per user).
 * - Prefetch: forecast + air quality for places requested in the last 24 h only.
 * Each job runs under a PostgreSQL advisory lock so several workers never duplicate it.
 */
@Module({ providers: CORE_PROVIDERS })
class WorkerModule {}

interface Job {
  name: string;
  lockId: number;
  everyMs: number;
  run: () => Promise<string>;
}

async function main() {
  const log = new Logger('Worker');
  const app = await NestFactory.createApplicationContext(WorkerModule, { logger: ['error', 'warn', 'log'] });
  app.enableShutdownHooks();
  const db = app.get(Db);
  const redis = app.get(RedisService);
  const snapshots = app.get(SnapshotService);
  const locations = app.get(LocationRepository);
  if (!redis.client) log.warn('REDIS_URL not set: the worker cannot share its cache with the API; jobs still run for smoke-testing.');

  const jobs: Job[] = [
    {
      name: 'noaa-kp',
      lockId: 727_101,
      everyMs: 5 * 60_000,
      run: async () => `bins=${(await snapshots.kp()).value.length}`,
    },
    {
      name: 'prefetch-active-locations',
      lockId: 727_102,
      everyMs: 15 * 60_000,
      run: async () => {
        const active = await locations.recentlyRequested(24, 500);
        let ok = 0;
        for (const loc of active) {
          const r = await Promise.allSettled([snapshots.forecast(loc), snapshots.airQuality(loc)]);
          if (r[0].status === 'fulfilled') ok++;
        }
        return `prefetched ${ok}/${active.length}`;
      },
    },
  ];

  const running = new Set<string>();
  const runJob = async (job: Job) => {
    if (running.has(job.name)) return;
    running.add(job.name);
    const client = await db.pool.connect();
    try {
      const got = (await client.query<{ ok: boolean }>('SELECT pg_try_advisory_lock($1) AS ok', [job.lockId])).rows[0].ok;
      if (!got) return;
      try {
        const t0 = Date.now();
        const msg = await job.run();
        log.log(`${job.name}: ${msg} (${Date.now() - t0} ms)`);
      } finally {
        await client.query('SELECT pg_advisory_unlock($1)', [job.lockId]);
      }
    } catch (e) {
      log.warn(`${job.name} failed: ${(e as Error).message}`);
    } finally {
      client.release();
      running.delete(job.name);
    }
  };

  const timers: NodeJS.Timeout[] = [];
  for (const job of jobs) {
    // Jitter avoids every worker hitting providers at the same second.
    const jitter = Math.floor(Math.random() * 10_000);
    timers.push(setTimeout(() => void runJob(job), jitter));
    timers.push(setInterval(() => void runJob(job), job.everyMs + jitter));
  }
  log.log(`worker started (providers: ${config.providerMode}, redis: ${redis.client ? 'on' : 'off'})`);

  const stop = async () => {
    timers.forEach((t) => clearTimeout(t));
    await app.close();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
