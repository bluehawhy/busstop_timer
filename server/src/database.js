import pg from 'pg';
import { AsyncLocalStorage } from 'node:async_hooks';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export async function openDatabase(connectionString = process.env.DATABASE_URL) {
  if (!connectionString) throw new Error('DATABASE_URL is required');
  const pool = new pg.Pool({ connectionString, max: 5, connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000, statement_timeout: 15000, idle_in_transaction_session_timeout: 30000,
    application_name: 'busstop-timer' });
  pool.on('error', error => console.error('PostgreSQL idle connection error:', error.code ?? 'UNKNOWN'));
  const context = new AsyncLocalStorage();
  const query = (sql, params = []) => (context.getStore()?.client ?? pool).query(sql, params);
  const db = {
    prepare(sql) {
      return {
        async all(...params) { return (await query(sql, params)).rows; },
        async get(...params) { return (await query(sql, params)).rows[0]; },
        async run(...params) { return { changes: (await query(sql, params)).rowCount }; },
      };
    },
    async exec(sql) {
      const scope=context.getStore();
      if (!scope) throw new Error('exec requires withConnection');
      const result=await query(sql);
      if (/^BEGIN\b/i.test(sql)) scope.inTransaction=true;
      if (/^(COMMIT|ROLLBACK)\b/i.test(sql)) scope.inTransaction=false;
      return result;
    },
    async withConnection(work) {
      if (context.getStore()) return work();
      const client = await pool.connect();
      return context.run({client,inTransaction:false}, async () => {
        let discard;
        try { return await work(); }
        finally {
          try { if(context.getStore().inTransaction) await client.query('ROLLBACK'); } catch (error) { discard = error; }
          client.release(discard);
        }
      });
    },
    async transaction(work) {
      return db.withConnection(async () => {
        if(context.getStore().inTransaction) throw new Error('Nested transaction is not supported');
        await db.exec('BEGIN');
        try { const result = await work(); await db.exec('COMMIT'); return result; }
        catch (error) { await db.exec('ROLLBACK'); throw error; }
      });
    },
    async close() { await pool.end(); },
  };
  try {
    await db.transaction(async () => {
      await query('SELECT pg_advisory_xact_lock(798231604)');
      await db.exec('CREATE TABLE IF NOT EXISTS schema_migrations(name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP)');
      const directory = fileURLToPath(new URL('../migrations/postgres/', import.meta.url));
      for (const name of readdirSync(directory).filter(n => n.endsWith('.sql')).sort()) {
        if (await db.prepare('SELECT name FROM schema_migrations WHERE name=$1').get(name)) continue;
        await db.exec(readFileSync(join(directory, name), 'utf8'));
        await db.prepare('INSERT INTO schema_migrations(name) VALUES ($1)').run(name);
      }
    });
    return db;
  } catch (error) { await pool.end(); throw error; }
}

export function legacyDatabase(db) {
  return { prepare(sql) {
    const statement = db.prepare(sql);
    let params = [];
    return { bind(...values) { params = values; return this; },
      async run() { return statement.run(...params); },
      async first() { return (await statement.get(...params)) ?? null; },
      async all() { return { results: await statement.all(...params) }; } };
  } };
}
