// src/repositories/service_logs.js — v6.0.0
const { query, one, many } = require('../config/db');
const { mapServiceLog } = require('../db/mappers');

const VALID_TYPES = ['refill', 'repair', 'inspection', 'installation', 'uninstall', 'other'];

async function listEnriched({ technicianId = null, deviceId = null, customerId = null, startDate = null, endDate = null } = {}) {
  const where = [];
  const vals = [];
  let n = 1;

  if (technicianId) { where.push(`sl.technician_id = $${n++}`); vals.push(technicianId); }
  if (deviceId)     { where.push(`sl.device_id = $${n++}`); vals.push(deviceId); }
  if (customerId)   { where.push(`d.customer_id = $${n++}`); vals.push(customerId); }
  if (startDate)    { where.push(`sl.created_at >= $${n++}`); vals.push(startDate); }
  if (endDate)      { where.push(`sl.created_at <= $${n++}`); vals.push(endDate); }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const rows = await many(
    `SELECT
        sl.*,
        d.name AS device_name,
        d.serial_number AS device_serial,
        c.name AS customer_name,
        u.name AS technician_name
      FROM service_logs sl
      LEFT JOIN devices d ON d.id = sl.device_id
      LEFT JOIN customers c ON c.id = d.customer_id
      LEFT JOIN users u ON u.id = sl.technician_id
      ${whereSql}
      ORDER BY sl.created_at DESC`,
    vals,
  );

  return rows.map((r) => mapServiceLog(r, {
    deviceName: r.device_name || '',
    deviceSerial: r.device_serial || '',
    customerName: r.customer_name || '',
    technicianName: r.technician_name || '',
  }));
}

async function create({ deviceId, technicianId, type, description = '', notes = '', photos = [] }) {
  if (!VALID_TYPES.includes(type)) {
    const err = new Error(`type ต้องเป็น: ${VALID_TYPES.join(', ')}`);
    err.statusCode = 400;
    throw err;
  }
  const row = await one(
    `INSERT INTO service_logs
       (device_id, technician_id, type, description, notes, photos)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb)
     RETURNING *`,
    [
      deviceId,
      technicianId,
      type,
      description,
      notes,
      JSON.stringify(Array.isArray(photos) ? photos.filter(Boolean) : []),
    ],
  );
  // Re-fetch enriched so the response matches the list shape.
  const enriched = await listEnriched({ deviceId: row.device_id });
  return enriched.find((log) => log.id === row.id) || mapServiceLog(row);
}

async function countAll() {
  const row = await one('SELECT COUNT(*)::int AS c FROM service_logs');
  return row ? row.c : 0;
}

async function countSince(date) {
  const row = await one(
    'SELECT COUNT(*)::int AS c FROM service_logs WHERE created_at >= $1',
    [date],
  );
  return row ? row.c : 0;
}

async function countByTypeSince(date) {
  const rows = await many(
    `SELECT type, COUNT(*)::int AS count
       FROM service_logs
      WHERE created_at >= $1
      GROUP BY type`,
    [date],
  );
  return Object.fromEntries(rows.map((r) => [r.type || 'unknown', r.count]));
}

async function dailyCountsSince(date) {
  return many(
    `SELECT
        to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS day,
        COUNT(*)::int AS count
      FROM service_logs
      WHERE created_at >= $1
      GROUP BY 1
      ORDER BY 1`,
    [date],
  );
}

module.exports = {
  VALID_TYPES,
  listEnriched,
  create,
  countAll,
  countSince,
  countByTypeSince,
  dailyCountsSince,
};
