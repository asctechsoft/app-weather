/**
 * npm run import:geonames -- [--dataset cities500] [--dry-run] [--approve-large-changes] [--source-dir <dir>]
 * Requires DATABASE_URL and an up-to-date schema (`npm run migrate`).
 */
import { Pool } from 'pg';
import { config } from '../config';
import { importGeoNames } from '../catalog/geonames.importer';

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  const dataset = arg('dataset') ?? 'cities500';
  if (!/^(cities(500|1000|5000|15000)|[A-Z]{2})$/.test(dataset)) throw new Error(`Unsupported dataset ${dataset}`);
  const pool = new Pool({ connectionString: config.databaseUrl, max: 2 });
  try {
    const r = await importGeoNames(pool, {
      dataset,
      dryRun: process.argv.includes('--dry-run'),
      approveLargeChanges: process.argv.includes('--approve-large-changes'),
      sourceDir: arg('source-dir'),
      baseUrl: config.geonamesBaseUrl,
      cacheDir: config.geonamesCacheDir,
      log: (m) => console.log(m),
    });
    console.log(JSON.stringify({ runId: r.runId, activated: r.activated, report: r.report, stats: r.stats }, null, 2));
  } finally {
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
