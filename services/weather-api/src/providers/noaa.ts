import { Injectable } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import { config } from '../config';
import { toIso } from '../common/time';
import { fetchJson, ProviderError } from './http';

export const NOAA_SWPC = 'noaa_swpc';

export interface KpBin {
  /** Start of the 3-hour Kp bin (UTC). */
  time: string;
  kp: number;
  kind: 'observed' | 'estimated' | 'predicted';
  noaaScale: string | null;
}

/** Planetary Kp is a global index — never a local value for the viewed city. */
@Injectable()
export class NoaaSwpcAdapter {
  readonly providerId = config.providerMode === 'fixture' ? 'fixture' : NOAA_SWPC;

  async kpForecast(): Promise<KpBin[]> {
    let raw: unknown;
    if (config.providerMode === 'fixture') {
      raw = JSON.parse(fs.readFileSync(path.join(config.fixtureDir, 'noaa-kp-forecast.json'), 'utf8'));
    } else {
      raw = await fetchJson<unknown>(NOAA_SWPC, `${config.noaaHost}/products/noaa-planetary-k-index-forecast.json`, 8000);
    }
    return parseKp(raw);
  }
}

export function parseKp(raw: unknown): KpBin[] {
  if (!Array.isArray(raw)) throw new ProviderError(NOAA_SWPC, 'MALFORMED');
  const rows: KpBin[] = [];
  for (const row of raw) {
    let timeTag: unknown;
    let kp: unknown;
    let kind: unknown;
    let scale: unknown;
    if (Array.isArray(row)) {
      [timeTag, kp, kind, scale] = row;
      if (timeTag === 'time_tag') continue;
    } else if (row && typeof row === 'object') {
      const o = row as Record<string, unknown>;
      timeTag = o.time_tag;
      kp = o.kp;
      kind = o.observed;
      scale = o.noaa_scale;
    } else continue;
    const ms = Date.parse(`${String(timeTag).replace(' ', 'T')}Z`);
    const kpv = Number(kp);
    if (!Number.isFinite(ms) || !Number.isFinite(kpv)) continue;
    const k = String(kind);
    rows.push({
      time: toIso(ms),
      kp: kpv,
      kind: k === 'observed' ? 'observed' : k === 'estimated' ? 'estimated' : 'predicted',
      noaaScale: scale ? String(scale) : null,
    });
  }
  if (!rows.length) throw new ProviderError(NOAA_SWPC, 'MALFORMED');
  return rows;
}
