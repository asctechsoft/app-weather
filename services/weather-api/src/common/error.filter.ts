import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import { randomUUID } from 'crypto';
import type { Request, Response } from 'express';
import { ApiError } from './errors';

/** Uniform error body; never forwards raw upstream errors (which may contain keys). */
@Catch()
export class ApiErrorFilter implements ExceptionFilter {
  private readonly log = new Logger('Error');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request & { requestId?: string }>();
    const requestId = req.requestId ?? randomUUID();
    let status = 500;
    let body: Record<string, unknown> = { code: 'INTERNAL', messageKey: 'error.internal' };
    if (exception instanceof ApiError) {
      status = exception.getStatus();
      body = { code: exception.code, messageKey: exception.messageKey, fieldErrors: exception.fieldErrors, retryAfterSeconds: exception.retryAfterSeconds };
      if (exception.retryAfterSeconds) res.setHeader('Retry-After', String(exception.retryAfterSeconds));
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      body = { code: status === 404 ? 'NOT_FOUND' : 'HTTP_ERROR', messageKey: status === 404 ? 'error.notFound' : 'error.http' };
    } else {
      this.log.error(`[${requestId}] ${(exception as Error)?.message ?? exception}`);
    }
    res.status(status).json({ ...body, requestId });
  }
}
