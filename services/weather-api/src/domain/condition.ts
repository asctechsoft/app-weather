import { ConditionCode } from './types';

/** WMO weather interpretation code → internal condition. Versioned; unknown codes map to UNKNOWN. */
export const CONDITION_MAPPING_VERSION = 'wmo-1';

const WMO: Record<number, ConditionCode> = {
  0: 'CLEAR',
  1: 'MOSTLY_CLEAR',
  2: 'PARTLY_CLOUDY',
  3: 'OVERCAST',
  45: 'FOG',
  48: 'FOG',
  51: 'DRIZZLE',
  53: 'DRIZZLE',
  55: 'DRIZZLE',
  56: 'FREEZING_RAIN',
  57: 'FREEZING_RAIN',
  61: 'RAIN',
  63: 'RAIN',
  65: 'RAIN',
  66: 'FREEZING_RAIN',
  67: 'FREEZING_RAIN',
  71: 'SNOW',
  73: 'SNOW',
  75: 'SNOW',
  77: 'SNOW',
  80: 'SHOWERS',
  81: 'SHOWERS',
  82: 'SHOWERS',
  85: 'SNOW',
  86: 'SNOW',
  95: 'THUNDERSTORM',
  96: 'THUNDERSTORM',
  99: 'THUNDERSTORM',
};

export function mapWmo(code: number | null | undefined): ConditionCode {
  if (code === null || code === undefined) return 'UNKNOWN';
  return WMO[code] ?? 'UNKNOWN';
}
