// src/config/db.js — PostgreSQL pool (v6.0.0)
// ─────────────────────────────────────────────────────────────
// Replaces the v5.x Mongoose/Mongo connection. Reads DATABASE_URL
// from the environment; for Supabase use the "Connection string —
// Transaction pooler" value (port 6543) in production, or the
// "Session pooler" (5432) if you need LISTEN/NOTIFY. A plain
// Postgres URL works too.
//
// SSL: Supabase requires TLS. We enable it automatically when
// DATABASE_URL contains sslmode=require OR when NODE_ENV=production,
// using rejectUnauthorized:false because Supabase rotates its
// certificate chain and shipping a pinned CA bundle is fragile.
// ─────────────────────────────────────────────────────────────
const { Pool } = require('pg');

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  process.stderr.write(
    '[FATAL] DATABASE_URL is not set. ' +
    'Point it at your Supabase/Postgres connection string in src/.env.\n'
  );
  process.exit(1);
}

const needsSsl =
  /sslmode=require/i.test(DATABASE_URL) ||
  (process.env.NODE_ENV || '').toLowerCase() === 'production' ||
  /supabase\.co/i.test(DATABASE_URL);

const pool = new Pool({
  connectionString: DATABASE_URL,
  ssl: needsSsl ? { rejectUnauthorized: false } : false,
  max: Number(process.env.PG_POOL_MAX || 10),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
});

pool.on('error', (err) => {
  process.stderr.write(`[pg pool error] ${err.message}\n`);
});

async function connectDB() {
  // Fail fast at boot if we can't reach the database.
  const client = await pool.connect();
  try {
    const { rows } = await client.query('SELECT now() AS now');
    process.stdout.write(`[INFO] ✅ Postgres connected (${rows[0].now})\n`);
  } finally {
    client.release();
  }
}

// Thin helpers — repositories use these instead of talking to pg directly.
async function query(text, params) {
  return pool.query(text, params);
}

async function one(text, params) {
  const { rows } = await pool.query(text, params);
  return rows[0] || null;
}

async function many(text, params) {
  const { rows } = await pool.query(text, params);
  return rows;
}

async function withTx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, connectDB, query, one, many, withTx };
