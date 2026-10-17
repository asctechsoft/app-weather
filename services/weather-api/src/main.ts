import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { randomUUID } from 'crypto';
import type { NextFunction, Request, Response } from 'express';
import { AppModule } from './app.module';
import { ApiErrorFilter } from './common/error.filter';
import { config } from './config';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { logger: ['error', 'warn', 'log'] });
  const origins = config.corsOrigins === '*' ? true : config.corsOrigins.split(',').map((s) => s.trim());
  app.enableCors({ origin: origins, allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'Accept-Language'], exposedHeaders: ['X-Request-Id', 'Retry-After'] });
  app.use((req: Request & { requestId?: string }, res: Response, next: NextFunction) => {
    req.requestId = randomUUID();
    res.setHeader('X-Request-Id', req.requestId);
    next();
  });
  app.useGlobalFilters(new ApiErrorFilter());
  app.enableShutdownHooks();
  await app.listen(config.port);
  new Logger('Bootstrap').log(`Weather API listening on :${config.port} (providers: ${config.providerMode})`);
}

bootstrap();
