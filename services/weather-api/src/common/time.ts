/**
 * Time helpers. All instants are stored as UTC; local dates/times are derived
 * through the location's IANA timezone (never the server or device timezone).
 */

export interface LocalParts {
  localDate: string; // YYYY-MM-DD
  localTime: string; // YYYY-MM-DDTHH:mm
  hour: number;
  utcOffsetSeconds: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    formatters.set(tz, f);
  }
  return f;
}

export function isValidTimezone(tz: string): boolean {
  try {
    formatter(tz);
    return true;
  } catch {
    return false;
  }
}

export function localParts(epochMs: number, tz: string): LocalParts {
  const parts: Record<string, string> = {};
  for (const p of formatter(tz).formatToParts(new Date(epochMs))) parts[p.type] = p.value;
  const localDate = `${parts.year}-${parts.month}-${parts.day}`;
  const hour = Number(parts.hour);
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    hour,
    Number(parts.minute),
    Number(parts.second),
  );
  const flooredMs = Math.floor(epochMs / 1000) * 1000;
  return {
    localDate,
    localTime: `${localDate}T${parts.hour}:${parts.minute}`,
    hour,
    utcOffsetSeconds: Math.round((asUtc - flooredMs) / 1000),
  };
}

export function toIso(epochMs: number): string {
  return new Date(epochMs).toISOString().replace('.000Z', 'Z');
}

/** Adds calendar days to a YYYY-MM-DD string (pure date arithmetic, DST-safe). */
export function addDays(localDate: string, days: number): string {
  const [y, m, d] = localDate.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return t.toISOString().slice(0, 10);
}

/** UTC instant of 00:00 local time on `localDate` in `tz` (handles DST days of 23/25 h). */
export function localDayStartMs(localDate: string, tz: string): number {
  const [y, m, d] = localDate.split('-').map(Number);
  const wall = Date.UTC(y, m - 1, d);
  let guess = wall - localParts(wall, tz).utcOffsetSeconds * 1000;
  for (let i = 0; i < 2; i++) guess = wall - localParts(guess, tz).utcOffsetSeconds * 1000;
  return guess;
}

export function isLocalDate(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
}
