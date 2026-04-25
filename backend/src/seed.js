// src/seed.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Wipes and seeds the Postgres schema with a single admin user.
// Safe to re-run; existing rows are truncated first.
//
//   node src/seed.js
//
// Assumes migrations/001_init.sql has already been applied.
// ─────────────────────────────────────────────────────────────
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const { pool, query } = require('./config/db');
const users = require('./repositories/users');

async function seed() {
  console.log('⚠️  ลบข้อมูลทั้งหมดใน 3 วินาที... (Ctrl+C เพื่อยกเลิก)');
  await new Promise((r) => setTimeout(r, 3000));

  // Order matters for FK constraints.
  await query('TRUNCATE TABLE fcm_tokens, notification_reads, notifications, service_logs, devices, customers, users RESTART IDENTITY CASCADE');

  await users.create({
    name: 'Admin',
    email: 'admin@scentandsense.com',
    password: 'password',
    role: 'admin',
  });

  console.log('\n✅ พร้อมใช้งาน');
  console.log('👤 admin@scentandsense.com / password');
  console.log('เข้าแอปแล้วเพิ่มลูกค้า/เครื่อง/ผู้ใช้จริง ได้เลย\n');

  await pool.end();
  process.exit(0);
}

seed().catch((e) => {
  console.error('❌', e);
  process.exit(1);
});
