// src/fcm/send.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Push notification sender. Uses the Admin SDK's sendEachForMulticast
// so we can deliver up to 500 tokens per call and surface per-token
// failures. Tokens that come back with messaging/registration-token-not-registered
// or messaging/invalid-registration-token are purged from the DB.
// ─────────────────────────────────────────────────────────────
const { getAdmin, isReady } = require('./admin');
const fcmTokens = require('../repositories/fcm_tokens');

const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

function log(level, msg) {
  const stream = level === 'error' ? process.stderr : process.stdout;
  stream.write(`[FCM] ${msg}\n`);
}

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function sendToTokens({ tokens, title, body, data = {} }) {
  if (!isReady()) return { sent: 0, failed: 0, dead: 0 };
  if (!Array.isArray(tokens) || tokens.length === 0) return { sent: 0, failed: 0, dead: 0 };

  const admin = getAdmin();
  const messaging = admin.messaging();

  // All data values must be strings per FCM contract.
  const stringData = Object.fromEntries(
    Object.entries(data || {}).map(([k, v]) => [k, v == null ? '' : String(v)]),
  );

  let sent = 0;
  let failed = 0;
  let dead = 0;

  for (const batch of chunk(tokens, 500)) {
    const message = {
      tokens: batch,
      notification: { title, body },
      data: stringData,
      android: {
        priority: 'high',
        notification: { channelId: 'scent_sense_alerts', sound: 'default' },
      },
      apns: {
        payload: { aps: { sound: 'default' } },
      },
    };

    try {
      const resp = await messaging.sendEachForMulticast(message);
      sent += resp.successCount;
      failed += resp.failureCount;

      const toDelete = [];
      resp.responses.forEach((r, i) => {
        if (!r.success) {
          const code = r.error && r.error.code;
          if (DEAD_TOKEN_CODES.has(code)) {
            toDelete.push(batch[i]);
          } else if (r.error) {
            log('warn', `send error (${code || 'unknown'}): ${r.error.message}`);
          }
        }
      });

      for (const dead_token of toDelete) {
        await fcmTokens.deleteToken(dead_token).catch(() => {});
      }
      dead += toDelete.length;
    } catch (err) {
      log('error', `batch send failed: ${err.message}`);
      failed += batch.length;
    }
  }

  if (sent || failed) {
    log('info', `push sent: ${sent} ok, ${failed} failed, ${dead} tokens pruned`);
  }
  return { sent, failed, dead };
}

async function sendToRoles({ roles, title, body, data = {} }) {
  if (!isReady()) return { sent: 0, failed: 0, dead: 0 };
  const tokens = await fcmTokens.listTokensForRoles(roles);
  if (!tokens.length) return { sent: 0, failed: 0, dead: 0 };
  return sendToTokens({ tokens, title, body, data });
}

async function sendToUser({ userId, title, body, data = {} }) {
  if (!isReady()) return { sent: 0, failed: 0, dead: 0 };
  const tokens = await fcmTokens.listTokensForUser(userId);
  if (!tokens.length) return { sent: 0, failed: 0, dead: 0 };
  return sendToTokens({ tokens, title, body, data });
}

module.exports = { sendToTokens, sendToRoles, sendToUser };
