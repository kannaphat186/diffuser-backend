// src/repositories/devices.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Replaces the Mongoose Device model. All reads return camelCase
// objects shaped like the v5.x API contract so the Flutter app
// doesn't need to care that the backing store changed.
// ─────────────────────────────────────────────────────────────
const { query, one, many } = require('../config/db');
const { mapDevice, DEVICE_WRITABLE_COLUMNS } = require('../db/mappers');

function esc(v = '') {
  return String(v).replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

async function findById(id) {
  const row = await one('SELECT * FROM devices WHERE id = $1', [id]);
  return row ? mapDevice(row) : null;
}

async function findRawById(id) {
  // Internal — used when we need to read a single column (e.g. device_token)
  // without going through the full mapper.
  return one('SELECT * FROM devices WHERE id = $1', [id]);
}

async function findBySerial(serial) {
  const row = await one('SELECT * FROM devices WHERE serial_number = $1', [serial]);
  return row ? mapDevice(row) : null;
}

async function findByHardwareId(hardwareId) {
  const row = await one('SELECT * FROM devices WHERE hardware_id = $1', [hardwareId]);
  return row ? mapDevice(row) : null;
}

async function listWithCustomers({
  customerId = null,
  status = null,
  search = null,
  skip = 0,
  limit = 500,
  paginated = false,
} = {}) {
  const where = [];
  const vals = [];
  let n = 1;

  if (customerId) { where.push(`customer_id = $${n++}`); vals.push(customerId); }
  if (status)     { where.push(`status = $${n++}`); vals.push(status); }

  if (search) {
    const like = `%${esc(search)}%`;
    where.push(`(
      name ILIKE $${n} ESCAPE '\\' OR
      serial_number ILIKE $${n} ESCAPE '\\' OR
      location ILIKE $${n} ESCAPE '\\' OR
      hardware_id ILIKE $${n} ESCAPE '\\' OR
      mac ILIKE $${n} ESCAPE '\\' OR
      wifi_ssid ILIKE $${n} ESCAPE '\\'
    )`);
    vals.push(like);
    n += 1;
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  vals.push(limit);
  vals.push(skip);

  const rows = await many(
    `SELECT d.*, c.name AS customer_name
       FROM devices d
       LEFT JOIN customers c ON c.id = d.customer_id
       ${whereSql}
       ORDER BY d.created_at DESC
       LIMIT $${n++} OFFSET $${n++}`,
    vals,
  );

  const data = rows.map((r) => mapDevice(r, r.customer_name || ''));

  if (paginated) {
    const countVals = vals.slice(0, vals.length - 2);
    const totalRow = await one(
      `SELECT COUNT(*)::int AS c FROM devices ${whereSql}`,
      countVals,
    );
    return { data, total: totalRow ? totalRow.c : 0 };
  }
  return { data };
}

async function countForCustomer(customerId, excludeId = null) {
  if (excludeId) {
    const row = await one(
      'SELECT COUNT(*)::int AS c FROM devices WHERE customer_id = $1 AND id <> $2',
      [customerId, excludeId],
    );
    return row ? row.c : 0;
  }
  const row = await one(
    'SELECT COUNT(*)::int AS c FROM devices WHERE customer_id = $1',
    [customerId],
  );
  return row ? row.c : 0;
}

// Apply a patch (camelCase → snake_case) atomically. Returns the
// updated row as a mapped Device, or null if the id didn't exist.
async function updateById(id, patch, { extraColumnMap = {} } = {}) {
  const map = { ...DEVICE_WRITABLE_COLUMNS, ...extraColumnMap };
  const sets = [];
  const vals = [];
  let n = 1;
  for (const [jsKey, sqlCol] of Object.entries(map)) {
    if (!(jsKey in patch)) continue;
    let val = patch[jsKey];
    if (sqlCol === 'schedule') {
      val = JSON.stringify(val || []);
    }
    sets.push(`${sqlCol} = $${n++}`);
    vals.push(val);
  }
  if (!sets.length) return findById(id);

  vals.push(id);
  const row = await one(
    `UPDATE devices SET ${sets.join(', ')} WHERE id = $${n} RETURNING *`,
    vals,
  );
  if (!row) return null;

  // Re-fetch with customer join so we can return the right shape cheaply.
  const joined = await one(
    `SELECT d.*, c.name AS customer_name
       FROM devices d
       LEFT JOIN customers c ON c.id = d.customer_id
       WHERE d.id = $1`,
    [id],
  );
  return mapDevice(joined, joined?.customer_name || '');
}

async function create(payload) {
  const map = DEVICE_WRITABLE_COLUMNS;
  const cols = ['id'];
  const placeholders = [];
  const vals = [];
  let n = 1;

  // Allow caller-supplied id (used on claim, when firmware already has its ObjectId).
  const id = payload._id || payload.id;
  if (id) {
    placeholders.push(`$${n++}`);
    vals.push(id);
  } else {
    // Use DB default (gen_random_uuid). Drop the column so DEFAULT fires.
    cols.pop();
  }

  for (const [jsKey, sqlCol] of Object.entries(map)) {
    if (!(jsKey in payload)) continue;
    let val = payload[jsKey];
    if (sqlCol === 'schedule') val = JSON.stringify(val || []);
    cols.push(sqlCol);
    placeholders.push(`$${n++}`);
    vals.push(val);
  }

  const row = await one(
    `INSERT INTO devices (${cols.join(', ')})
     VALUES (${placeholders.join(', ')})
     RETURNING *`,
    vals,
  );
  return mapDevice(row);
}

async function deleteById(id) {
  const { rowCount } = await query('DELETE FROM devices WHERE id = $1', [id]);
  return rowCount > 0;
}

async function markStaleOffline(cutoff, limit = 500) {
  // Returns the rows that were flipped offline. A single UPDATE keeps
  // this cheap; the offline monitor then feeds these into the
  // notification grace queue.
  const rows = await many(
    `UPDATE devices
       SET status = 'offline'
       WHERE status <> 'offline'
         AND (last_seen_at IS NULL OR last_seen_at < $1)
         AND (last_sensor_update IS NULL OR last_sensor_update < $1)
       RETURNING id, name, serial_number, status, is_on, level, level_ml, battery, customer_id`,
    [cutoff],
  );
  // Respect the `limit` at the application level so we don't run
  // away on a cold backend boot. Postgres can't LIMIT an UPDATE
  // without a sub-select; the simple form above is fine for the
  // tens-to-hundreds scale this product operates at.
  return rows.slice(0, limit).map((r) => ({
    id: r.id,
    name: r.name,
    serialNumber: r.serial_number,
    status: r.status,
    isOn: r.is_on,
    level: r.level,
    levelMl: r.level_ml,
    battery: r.battery,
    customerId: r.customer_id,
  }));
}

async function summary() {
  const row = await one(`
    SELECT
      COUNT(*)::int AS total_devices,
      SUM(CASE WHEN status = 'online' THEN 1 ELSE 0 END)::int AS online_devices,
      SUM(CASE WHEN is_on THEN 1 ELSE 0 END)::int AS active_devices,
      SUM(CASE WHEN level < 20 OR pump_ok = false OR relay_ok = false THEN 1 ELSE 0 END)::int AS alert_devices,
      COALESCE(AVG(level), 0)::float AS avg_level
    FROM devices
  `);
  return row || {
    total_devices: 0,
    online_devices: 0,
    active_devices: 0,
    alert_devices: 0,
    avg_level: 0,
  };
}

async function levelPerDevice() {
  return many(
    'SELECT id, name, serial_number, level, level_ml FROM devices ORDER BY created_at DESC',
  );
}

async function countOnline() {
  const row = await one("SELECT COUNT(*)::int AS c FROM devices WHERE status = 'online'");
  return row ? row.c : 0;
}

async function searchGlobal(qText, limit = 100) {
  const like = `%${esc(qText)}%`;
  const rows = await many(
    `SELECT d.*, c.name AS customer_name
       FROM devices d
       LEFT JOIN customers c ON c.id = d.customer_id
      WHERE d.name ILIKE $1 ESCAPE '\\'
         OR d.serial_number ILIKE $1 ESCAPE '\\'
         OR d.location ILIKE $1 ESCAPE '\\'
         OR d.wifi_ssid ILIKE $1 ESCAPE '\\'
         OR d.hardware_id ILIKE $1 ESCAPE '\\'
         OR d.mac ILIKE $1 ESCAPE '\\'
      LIMIT $2`,
    [like, limit],
  );
  return rows.map((r) => mapDevice(r, r.customer_name || ''));
}

module.exports = {
  findById,
  findRawById,
  findBySerial,
  findByHardwareId,
  listWithCustomers,
  countForCustomer,
  updateById,
  create,
  deleteById,
  markStaleOffline,
  summary,
  levelPerDevice,
  countOnline,
  searchGlobal,
};
