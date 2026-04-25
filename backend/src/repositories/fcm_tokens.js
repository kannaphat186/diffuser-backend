// src/repositories/fcm_tokens.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// One row per FCM registration token. Upsert on token so a
// re-registration after logout/login moves the token to the
// current user without creating duplicates.
// ─────────────────────────────────────────────────────────────
const { query, many } = require('../config/db');

async function upsert({ token, userId, platform = 'android' }) {
  if (!token || !userId) return;
  await query(
    `INSERT INTO fcm_tokens (token, user_id, platform)
       VALUES ($1, $2, $3)
     ON CONFLICT (token) DO UPDATE
        SET user_id = EXCLUDED.user_id,
            platform = EXCLUDED.platform`,
    [token, userId, platform],
  );
}

async function deleteToken(token) {
  await query('DELETE FROM fcm_tokens WHERE token = $1', [token]);
}

async function listTokensForRoles(roles) {
  if (!Array.isArray(roles) || !roles.length) return [];
  const rows = await many(
    `SELECT t.token
       FROM fcm_tokens t
       JOIN users u ON u.id = t.user_id
      WHERE u.role = ANY($1::text[])`,
    [roles],
  );
  return rows.map((r) => r.token);
}

async function listTokensForUser(userId) {
  const rows = await many(
    'SELECT token FROM fcm_tokens WHERE user_id = $1',
    [userId],
  );
  return rows.map((r) => r.token);
}

module.exports = { upsert, deleteToken, listTokensForRoles, listTokensForUser };
