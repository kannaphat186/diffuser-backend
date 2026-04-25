// src/migrate.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Applies every .sql file in backend/migrations/ in order.
// Idempotent — all DDL uses IF NOT EXISTS / CREATE OR REPLACE.
//
//   npm run migrate
// ─────────────────────────────────────────────────────────────
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const { pool } = require('./config/db');

async function run() {
  const dir = path.resolve(__dirname, '..', 'migrations');
  if (!fs.existsSync(dir)) {
    console.error(`[migrate] migrations directory not found: ${dir}`);
    process.exit(1);
  }
  const files = fs.readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const f of files) {
    const full = path.join(dir, f);
    const sql = fs.readFileSync(full, 'utf8');
    console.log(`[migrate] applying ${f} ...`);
    await pool.query(sql);
  }

  console.log('[migrate] done.');
  await pool.end();
  process.exit(0);
}

run().catch((err) => {
  console.error('[migrate] failed:', err.message);
  process.exit(1);
});
