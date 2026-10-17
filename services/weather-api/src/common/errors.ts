import { HttpException } from '@nestjs/common';

export interface FieldError {
  field: string;
  messageKey: string;
}

/** Error body per spec §10.2: code, messageKey, requestId, retryAfterSeconds, fieldErrors. */
export class ApiError extends HttpException {
  constructor(
    status: number,
    readonly code: string,
    readonly messageKey: string,
    readonly fieldErrors?: FieldError[],
    readonly retryAfterSeconds?: number,
  ) {
    super({ code, messageKey }, status);
  }
}

export const badRequest = (field: string, messageKey: string) =>
  new ApiError(400, 'INVALID_INPUT', 'error.invalidInput', [{ field, messageKey }]);

export const notFound = (code: string) => new ApiError(404, code, `error.${code}`);

export const upstreamUnavailable = () =>
  new ApiError(503, 'UPSTREAM_UNAVAILABLE', 'error.upstreamUnavailable', undefined, 60);
