// src/utils/device-notifications.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Same alert rules as v5.2.5. What changed:
//   • Data access moved from the Mongoose Notification model to
//     the notifications repository (Postgres).
//   • After a NEW notification is created (not a dedupe update),
//     an FCM push is fanned out to the target roles. Dedupe
//     updates do not re-push — that's what the dedupe window
//     is for.
// ─────────────────────────────────────────────────────────────
const notifications = require('../repositories/notifications');
const fcm = require('../fcm/send');

const ALERT_ROLES = ['admin', 'manager', 'technician'];
const DEDUPE_WINDOW_MINUTES = Number(process.env.NOTIFICATION_DEDUPE_MINUTES || 30);
const RULE_TYPES = ['critical_level', 'low_level', 'device_offline', 'pump_failure', 'relay_failure'];

function buildRules(device) {
  const rules = [];
  const label = device.name || device.serialNumber;

  if (device.level != null && device.level <= 10) {
    rules.push({
      type: 'critical_level',
      title: 'น้ำหอมใกล้หมด — ต้องเติมทันที!',
      message: `${label} (${device.serialNumber}) เหลือน้ำหอมเพียง ${device.level}% — ต้องเติมทันที!`,
    });
  } else if (device.level != null && device.level <= 15) {
    rules.push({
      type: 'low_level',
      title: 'น้ำหอมเหลือน้อย — ควรเติมเร็วๆ นี้',
      message: `${label} (${device.serialNumber}) เหลือน้ำหอม ${device.level}% — กรุณาเติมเร็วๆ นี้`,
    });
  }

  if (device.status === 'offline') {
    rules.push({
      type: 'device_offline',
      title: 'เครื่องออฟไลน์',
      message: `${label} (${device.serialNumber}) ออฟไลน์ — ตรวจสอบ WiFi และไฟฟ้า`,
    });
  }

  if (device.pumpOk === false) {
    rules.push({
      type: 'pump_failure',
      title: 'ปั๊มหยุดทำงาน',
      message: `${label} (${device.serialNumber}) — แรงดันปั๊มต่ำ อาจเกิดจากไดอะแฟรมสึกหรอ ควรเรียกช่างตรวจสอบ`,
    });
  }

  if (device.relayOk === false) {
    rules.push({
      type: 'relay_failure',
      title: 'รีเลย์หยุดทำงาน',
      message: `${label} (${device.serialNumber}) — รีเลย์ไม่ตอบสนอง อาจเกิดจากวงจรขาด ควรตรวจสอบด้านไฟฟ้า`,
    });
  }

  return rules;
}

async function ensureNotification({ device, type, title, message, targetRoles = ALERT_ROLES }) {
  const since = new Date(Date.now() - DEDUPE_WINDOW_MINUTES * 60 * 1000);
  const existing = await notifications.findRecentByTypeAndDevice({
    type,
    deviceId: device?.id || null,
    since,
  });

  if (existing) {
    const nextDeviceName = device?.name || device?.serialNumber || '';
    if (existing.title !== title || existing.message !== message || existing.device_name !== nextDeviceName) {
      await notifications.updateTitleAndMessage(existing.id, {
        title,
        message,
        deviceName: nextDeviceName,
      });
    }
    return { notification: existing, created: false };
  }

  const created = await notifications.create({
    title,
    message,
    type,
    deviceId: device?.id || null,
    deviceName: device?.name || device?.serialNumber || '',
    targetRoles,
  });
  return { notification: created, created: true };
}

async function fanOutPush({ rule, device, targetRoles }) {
  try {
    await fcm.sendToRoles({
      roles: targetRoles,
      title: rule.title,
      body: rule.message,
      data: {
        type: rule.type,
        deviceId: device?.id || '',
        deviceSerial: device?.serialNumber || '',
      },
    });
  } catch (err) {
    process.stderr.write(`[FCM] fanout failed: ${err.message}\n`);
  }
}

async function syncDeviceNotifications(device) {
  if (!device) return { created: [], cleared: 0 };

  const rules = buildRules(device);
  const activeTypes = new Set(rules.map((rule) => rule.type));

  const resolvedTypes = RULE_TYPES.filter((t) => !activeTypes.has(t));
  const cleared = await notifications.deleteResolvedForDevice(device.id, resolvedTypes);

  const createdList = [];
  for (const rule of rules) {
    const { notification, created } = await ensureNotification({
      device,
      ...rule,
    });
    createdList.push(notification);

    // Only push on genuinely new alerts — re-surfacing an existing one
    // would spam users every time a sensor packet comes in.
    if (created) {
      await fanOutPush({ rule, device, targetRoles: ALERT_ROLES });
    }
  }

  return { created: createdList, cleared };
}

module.exports = {
  ALERT_ROLES,
  RULE_TYPES,
  buildRules,
  ensureNotification,
  syncDeviceNotifications,
};
