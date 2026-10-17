import { createHash } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { Client } from 'pg';

/** Arbitrary constant: serialises concurrent deploys running migrations. */
const LOCK_ID = 727_001;
export const MIGRATIONS_DIR = path.resolve(__dirname, '../../migrations');

/**
 * Applies pending `migrations/NNN_name.sql` files in order, each in its own transaction,
 * under a session advisory lock. Applied files are checksummed; editing an applied
 * migration is an error (write a new one instead).
 */
export async function migrate(databaseUrl: string, log: (m: string) => void = console.log): Promise<string[]> {
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  const applied: string[] = [];
  try {
    // Place names (Hà Nội, Đà Nẵng, ...) require UTF-8; refuse to migrate anything else.
    const enc = (await client.query<{ server_encoding: string }>('SHOW server_encoding')).rows[0].server_encoding;
    if (enc.toUpperCase() !== 'UTF8') throw new Error(`Database encoding is ${enc}; create it with ENCODING 'UTF8'`);
    await client.query('SELECT pg_advisory_lock($1)', [LOCK_ID]);
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`);
    const done = new Map((await client.query<{ name: string; checksum: string }>('SELECT name, checksum FROM schema_migrations')).rows.map((r) => [r.name, r.checksum]));
    const files = fs.readdirSync(MIGRATIONS_DIR).filter((f) => /^\d{3}_[\w-]+\.sql$/.test(f)).sort();
    for (const file of files) {
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      const sum = createHash('sha256').update(sql).digest('hex');
      const prev = done.get(file);
      if (prev) {
        if (prev !== sum) throw new Error(`Migration ${file} was modified after being applied`);
        continue;
      }
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)', [file, sum]);
        await client.query('COMMIT');
      } catch (e) {
        await client.query('ROLLBACK');
        throw new Error(`Migration ${file} failed: ${(e as Error).message}`);
      }
      applied.push(file);
      log(`applied ${file}`);
    }
    if (!applied.length) log('database is up to date');
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [LOCK_ID]).catch(() => undefined);
    await client.end();
  }
  return applied;
}

if (require.main === module) {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { config } = require('../config');
  migrate(config.databaseUrl).catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
