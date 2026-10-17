/**
 * Local PostgreSQL without Docker (dev only): `npm run db:dev`.
 * Starts an embedded PostgreSQL in ./data/pg on port 54329 and keeps it running.
 * Use `infra/docker-compose.yml` instead when Docker is available.
 */
import * as path from 'path';

async function main() {
  // Loaded lazily: dev-only dependency.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const EmbeddedPostgres = require('embedded-postgres').default;
  const dir = path.resolve(process.env.DEV_DB_DIR ?? './data/pg');
  const port = Number(process.env.DEV_DB_PORT ?? 54329);
  const pg = new EmbeddedPostgres({ databaseDir: dir, user: 'skyweather', password: 'skyweather_dev', port, persistent: true, onLog: () => undefined, initdbFlags: ['--encoding=UTF8', '--locale=C'] });
  const fs = await import('fs');
  if (!fs.existsSync(path.join(dir, 'PG_VERSION'))) await pg.initialise();
  await pg.start();
  try {
    await pg.createDatabase('skyweather');
  } catch {
    /* already exists */
  }
  console.log(`DATABASE_URL=postgres://skyweather:skyweather_dev@127.0.0.1:${port}/skyweather`);
  const stop = async () => {
    await pg.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  setInterval(() => undefined, 1 << 30);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
