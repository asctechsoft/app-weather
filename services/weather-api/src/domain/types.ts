/** Canonical SkyWeather contract (schema 1.0). Canonical units: °C, m/s, mm, hPa, m, %, degree, µg/m³. */

export const SCHEMA_VERSION = '1.0';

export type SectionStatus = 'ready' | 'empty' | 'unsupported' | 'stale' | 'error';
export type DataKind = 'model' | 'observation' | 'derived' | 'computed';

export type ConditionCode =
  | 'CLEAR'
  | 'MOSTLY_CLEAR'
  | 'PARTLY_CLOUDY'
  | 'OVERCAST'
  | 'FOG'
  | 'DRIZZLE'
  | 'RAIN'
  | 'FREEZING_RAIN'
  | 'SNOW'
  | 'SHOWERS'
  | 'THUNDERSTORM'
  | 'UNKNOWN';

export interface SourceMeta {
  providerId: string;
  dataKind: DataKind;
  validAt?: string | null;
  validRange?: { from: string; to: string } | null;
  fetchedAt: string | null;
  expiresAt: string | null;
  modelRunAt?: string | null;
}

export interface Section<T> {
  status: SectionStatus;
  reasonCode: string | null;
  source: SourceMeta | null;
  data: T | null;
}

export type LocationKind = 'city' | 'administrative_area' | 'gps' | 'place';

export interface Location {
  locationId: string;
  kind: LocationKind;
  name: string | null;
  countryCode: string | null;
  country: string | null;
  admin1: string | null;
  latitude: number;
  longitude: number;
  timezone: string;
  coordinateSource: 'catalog' | 'geocoding' | 'gps';
  externalIds: { provider: string; externalId: string }[];
}

export interface CurrentData {
  validAt: string;
  temperatureC: number | null;
  feelsLikeC: number | null;
  humidityPct: number | null;
  dewPointC: number | null;
  conditionCode: ConditionCode;
  rawConditionCode: number | null;
  isDay: boolean | null;
  windSpeedMs: number | null;
  windDirectionDeg: number | null;
  windGustMs: number | null;
  seaLevelPressureHpa: number | null;
  surfacePressureHpa: number | null;
  cloudCoverPct: number | null;
  visibilityM: number | null;
  uvIndex: number | null;
  precipitationMm: number | null;
}

export interface HourlyRecord {
  /** Start of the hour (UTC). Instantaneous values are valid at this instant. */
  time: string;
  localTime: string;
  localDate: string;
  utcOffsetSeconds: number;
  /** Precipitation amount covers the preceding hour: [intervalStartAt, intervalEndAt). */
  intervalStartAt: string;
  intervalEndAt: string;
  temperatureC: number | null;
  feelsLikeC: number | null;
  humidityPct: number | null;
  dewPointC: number | null;
  rainProbabilityPct: number | null;
  precipitationMm: number | null;
  conditionCode: ConditionCode;
  rawConditionCode: number | null;
  isDay: boolean | null;
  seaLevelPressureHpa: number | null;
  surfacePressureHpa: number | null;
  cloudCoverPct: number | null;
  visibilityM: number | null;
  windSpeedMs: number | null;
  windDirectionDeg: number | null;
  windGustMs: number | null;
  uvIndex: number | null;
}

export interface DailyRecord {
  localDate: string;
  startAt: string;
  endAt: string;
  conditionCode: ConditionCode;
  rawConditionCode: number | null;
  minC: number | null;
  maxC: number | null;
  feelsMinC: number | null;
  feelsMaxC: number | null;
  sunriseAt: string | null;
  sunsetAt: string | null;
  daylightSeconds: number | null;
  uvIndexMax: number | null;
  precipitationTotalMm: number | null;
  rainProbabilityMaxPct: number | null;
  windSpeedMaxMs: number | null;
  windGustMaxMs: number | null;
  windDirectionDominantDeg: number | null;
}

export interface ForecastSnapshot {
  timezone: string;
  requestedCoordinate: { latitude: number; longitude: number };
  dataCoordinate: { latitude: number; longitude: number };
  elevationM: number | null;
  current: CurrentData | null;
  hourly: HourlyRecord[];
  daily: DailyRecord[];
  fetchedAt: string;
}

export interface AirQualityHour {
  time: string;
  localTime: string;
  localDate: string;
  usAqi: number | null;
  pm25: number | null;
  pm10: number | null;
  no2: number | null;
  o3: number | null;
}

export interface AirQualitySnapshot {
  current: (Omit<AirQualityHour, 'localTime' | 'localDate'> & { validAt: string }) | null;
  hourly: AirQualityHour[];
  fetchedAt: string;
  dataCoordinate: { latitude: number; longitude: number };
}
