// src/repositories/notifications.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Notification list: role-scoped (admin sees all, others see only
// notifications whose target_roles JSONB array contains their role).
// Read state is per-user via the notification_reads table.
// ─────────────────────────────────────────────────────────────
const { query, one, many } = require('../config/db');
const { mapNotification } = require('../db/mappers');

function roleFilter(role) {
  // Admin sees all, others are restricted to target_roles @> [role].
  if (role === 'admin') return { clause: '', params: [] };
  return {
    clause: 'AND n.target_roles @> $ROLE_PARAM::jsonb',
    params: [JSON.stringify([role])],
  };
}

async function listForUser({ userId, role, limit = 50 }) {
  const roleF = roleFilter(role);
  const params = [userId, limit, ...roleF.params];
  const clause = roleF.clause.replace('$ROLE_PARAM', '3');
  const rows = await many(
    `SELECT n.*, r.read_at
       FROM notifications n
       LEFT JOIN notification_reads r
              ON r.notification_id = n.id AND r.user_id = $1
      WHERE true ${clause}
      ORDER BY n.created_at DESC
      LIMIT $2`,
    params,
  );
  return rows.map((row) => mapNotification(row, userId));
}

async function findByIdForUser(id, { userId, role }) {
  const roleF = roleFilter(role);
  const params = [id, userId, ...roleF.params];
  const clause = roleF.clause.replace('$ROLE_PARAM', '3');
  const row = await one(
    `SELECT n.*, r.read_at
       FROM notifications n
       LEFT JOIN notification_reads r
              ON r.notification_id = n.id AND r.user_id = $2
      WHERE n.id = $1 ${clause}
      LIMIT 1`,
    params,
  );
  return row ? mapNotification(row, userId) : null;
}

async function markRead(id, userId) {
  await query(
    `INSERT INTO notification_reads (notification_id, user_id)
       VALUES ($1, $2)
     ON CONFLICT (notification_id, user_id) DO NOTHING`,
    [id, userId],
  );
}

async function markAllRead({ userId, role }) {
  // Add an (n.id, userId) row for every notification this user is
  // allowed to see. Duplicates are ignored.
  const roleF = roleFilter(role);
  const params = [userId, ...roleF.params];
  const clause = roleF.clause.replace('$ROLE_PARAM', '2');
  await query(
    `INSERT INTO notification_reads (notification_id, user_id)
       SELECT n.id, $1
         FROM notifications n
        WHERE true ${clause}
     ON CONFLICT (notification_id, user_id) DO NOTHING`,
    params,
  );
}

async function deleteForUser(id, { userId, role }) {
  // Admin delete is global. Everyone else only "dismisses" the
  // notification by marking it read — the v5.x API behaved the same way.
  if (role === 'admin') {
    const { rowCount } = await query('DELETE FROM notifications WHERE id = $1', [id]);
    return rowCount > 0;
  }
  const found = await findByIdForUser(id, { userId, role });
  if (!found) return false;
  await markRead(id, userId);
  return true;
}

async function deleteAllForUser({ userId, role }) {
  if (role === 'admin') {
    await query('DELETE FROM notifications');
    return;
  }
  await markAllRead({ userId, role });
}

// Dedupe helper used by the alert syncer.
async function findRecentByTypeAndDevice({ type, deviceId, since }) {
  const row = await one(
    `SELECT * FROM notifications
       WHERE type = $1
         AND (
           ($2::text IS NULL AND device_id IS NULL) OR
           device_id = $2
         )
         AND created_at >= $3
     ORDER BY created_at DESC
        LIMIT 1`,
    [type, deviceId || null, since],
  );
  return row;
}

async function updateTitleAndMessage(id, { title, message, deviceName }) {
  await query(
    `UPDATE notifications
        SET title = $1, message = $2, device_name = $3
      WHERE id = $4`,
    [title, message, deviceName || '', id],
  );
}

async function create({ title, message, type, deviceId, deviceName, targetRoles }) {
  const row = await one(
    `INSERT INTO notifications
       (title, message, type, device_id, device_name, target_roles)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb)
     RETURNING *`,
    [
      title,
      message,
      type,
      deviceId || null,
      deviceName || '',
      JSON.stringify(Array.isArray(targetRoles) ? targetRoles : []),
    ],
  );
  return row;
}

async function deleteResolvedForDevice(deviceId, resolvedTypes) {
  if (!deviceId || !resolvedTypes || !resolvedTypes.length) return 0;
  const { rowCount } = await query(
    `DELETE FROM notifications
       WHERE device_id = $1
         AND type = ANY($2::text[])`,
    [deviceId, resolvedTypes],
  );
  return rowCount || 0;
}

async function countSince(date) {
  const row = await one(
    'SELECT COUNT(*)::int AS c FROM notifications WHERE created_at >= $1',
    [date],
  );
  return row ? row.c : 0;
}

module.exports = {
  listForUser,
  findByIdForUser,
  markRead,
  markAllRead,
  deleteForUser,
  deleteAllForUser,
  findRecentByTypeAndDevice,
  updateTitleAndMessage,
  create,
  deleteResolvedForDevice,
  countSince,
};
