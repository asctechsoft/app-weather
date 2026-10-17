import { CanActivate, ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { config } from '../config';
import { ApiError } from '../common/errors';
import { RedisService } from '../common/redis';
import { Installation, InstallationsService } from './installations.service';

export const PUBLIC_KEY = 'skyweather:public';
/** Marks a route as callable without an installation token (health, registration). */
export const Public = () => SetMetadata(PUBLIC_KEY, true);

export type AuthedRequest = Request & { installation?: Installation; requestId?: string };

/**
 * Fixed-window rate limiter keyed by installation (or client IP for public routes).
 * Uses Redis INCR when available so limits hold across instances.
 */
@Injectable()
export class RateLimiter {
  private readonly windows = new Map<string, { n: number; resetAt: number }>();

  constructor(private readonly redis: RedisService) {}

  /** Returns seconds to wait when the limit is exceeded, otherwise 0. */
  async hit(key: string, limit: number, windowMs = 60_000): Promise<number> {
    const now = Date.now();
    const bucket = Math.floor(now / windowMs);
    const resetAt = (bucket + 1) * windowMs;
    if (this.redis.client) {
      try {
        const k = `rl:${key}:${bucket}`;
        const n = await this.redis.client.incr(k);
        if (n === 1) await this.redis.client.pexpire(k, windowMs);
        return n > limit ? Math.ceil((resetAt - now) / 1000) : 0;
      } catch {
        /* fall through to local window */
      }
    }
    const w = this.windows.get(key);
    if (!w || w.resetAt <= now) {
      this.windows.set(key, { n: 1, resetAt });
      if (this.windows.size > 50_000) this.windows.clear();
      return 0;
    }
    w.n++;
    return w.n > limit ? Math.ceil((w.resetAt - now) / 1000) : 0;
  }
}

@Injectable()
export class InstallationGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly installations: InstallationsService,
    private readonly limiter: RateLimiter,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const isPublic = this.reflector.getAllAndOverride<boolean>(PUBLIC_KEY, [ctx.getHandler(), ctx.getClass()]);
    if (isPublic) {
      const wait = await this.limiter.hit(`ip:${req.ip}`, 30);
      if (wait) throw new ApiError(429, 'RATE_LIMITED', 'error.rateLimited', undefined, wait);
      return true;
    }
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7).trim() : undefined;
    const inst = await this.installations.authenticate(token);
    const wait = await this.limiter.hit(`inst:${inst.installationId}`, config.rateLimitPerMinute);
    if (wait) throw new ApiError(429, 'RATE_LIMITED', 'error.rateLimited', undefined, wait);
    req.installation = inst;
    return true;
  }
}
