// src/repositories/customers.js — v6.0.0
const { query, one, many } = require('../config/db');
const { mapCustomer } = require('../db/mappers');

function esc(v = '') {
  return String(v).replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

async function findById(id) {
  const row = await one('SELECT * FROM customers WHERE id = $1', [id]);
  return mapCustomer(row);
}

async function listSearch(q = '') {
  const trimmed = String(q || '').trim();
  if (!trimmed) {
    const rows = await many(
      'SELECT * FROM customers ORDER BY created_at DESC',
    );
    return rows;
  }
  const like = `%${esc(trimmed)}%`;
  const rows = await many(
    `SELECT * FROM customers
       WHERE name ILIKE $1 ESCAPE '\\'
          OR address ILIKE $1 ESCAPE '\\'
          OR contact_name ILIKE $1 ESCAPE '\\'
       ORDER BY created_at DESC`,
    [like],
  );
  return rows;
}

// Aggregate device counts per customer — replaces the Mongo $group
// aggregation used to build the customer list.
async function buildStatsMap() {
  const rows = await many(`
    SELECT
      customer_id,
      COUNT(*)::int AS device_count,
      SUM(CASE WHEN status = 'online' THEN 1 ELSE 0 END)::int AS online_count,
      SUM(CASE
        WHEN level < 20
          OR pump_ok = false
          OR relay_ok = false
          OR status = 'offline'
        THEN 1 ELSE 0
      END)::int AS alert_count
    FROM devices
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
  `);
  const map = new Map();
  for (const r of rows) {
    map.set(r.customer_id, {
      deviceCount: r.device_count,
      onlineCount: r.online_count,
      alertCount: r.alert_count,
    });
  }
  return map;
}

async function create(input) {
  const {
    name,
    contactName = '',
    contactPhone = '',
    contactEmail = '',
    address = '',
    packageQty = 0,
    notes = '',
  } = input;
  const row = await one(
    `INSERT INTO customers
       (name, contact_name, contact_phone, contact_email, address, package_qty, notes)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING *`,
    [name, contactName, contactPhone, contactEmail, address, packageQty, notes],
  );
  return mapCustomer(row);
}

async function updateById(id, patch) {
  const map = {
    name: 'name',
    contactName: 'contact_name',
    contactPhone: 'contact_phone',
    contactEmail: 'contact_email',
    address: 'address',
    packageQty: 'package_qty',
    notes: 'notes',
  };
  const sets = [];
  const vals = [];
  let n = 1;
  for (const [k, col] of Object.entries(map)) {
    if (patch[k] !== undefined) {
      sets.push(`${col} = $${n++}`);
      vals.push(patch[k]);
    }
  }
  if (!sets.length) return findById(id);
  vals.push(id);
  const row = await one(
    `UPDATE customers SET ${sets.join(', ')} WHERE id = $${n} RETURNING *`,
    vals,
  );
  return mapCustomer(row);
}

async function deleteById(id) {
  const { rowCount } = await query('DELETE FROM customers WHERE id = $1', [id]);
  return rowCount > 0;
}

async function countById(id) {
  const row = await one('SELECT COUNT(*)::int AS c FROM customers WHERE id = $1', [id]);
  return row ? row.c : 0;
}

async function countAll() {
  const row = await one('SELECT COUNT(*)::int AS c FROM customers');
  return row ? row.c : 0;
}

module.exports = {
  findById,
  listSearch,
  buildStatsMap,
  create,
  updateById,
  deleteById,
  countById,
  countAll,
  mapCustomer,
};
