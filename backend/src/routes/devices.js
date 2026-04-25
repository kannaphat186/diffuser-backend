// src/routes/devices.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Full rewrite against the devices/customers repositories.
// Behaviour preserved from v5.2.5:
//   • Manual POST /api/devices returns 410 — onboarding is the only path.
//   • POST /api/devices/claim enforces hardware identity and capacity.
//   • ESP32 endpoints (/state, /sensor, /hw-toggle, /schedule-from-hw)
//     use the x-device-token / shared-secret middleware.
//   • Offline status is re-asserted from the sensor feed with
//     lastSeenAt / lastSensorUpdate stamps; the monitor in server.js
//     drives the grace-period offline detection.
// ─────────────────────────────────────────────────────────────
const router = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const devices = require('../repositories/devices');
const customers = require('../repositories/customers');
const { syncDeviceNotifications } = require('../utils/device-notifications');

const normalizeString = (value, fallback = '') => {
  if (value === undefined || value === null) return fallback;
  return String(value).trim();
};

const buildLevelPct = (levelMl, installedTankMl) => {
  if (typeof levelMl !== 'number') return undefined;
  const tank = Number(installedTankMl) > 0 ? Number(installedTankMl) : 1000;
  return Math.max(0, Math.min(100, Math.round((levelMl / tank) * 100)));
};

function emitDeviceUpdate(req, device) {
  const io = req.app.get('io');
  if (!io) return;
  io.emit('device:updated', {
    id: device.id,
    name: device.name,
    customerId: device.customerId || null,
    location: device.location,
    isOn: device.isOn,
    level: device.level,
    levelMl: device.levelMl,
    battery: device.battery,
    batteryVoltage: device.batteryVoltage,
    status: device.status,
    wifiSSID: device.wifiSSID,
    wifiIP: device.wifiIP,
    signalStrength: device.signalStrength,
    pumpOk: device.pumpOk,
    relayOk: device.relayOk,
    btConnected: device.btConnected,
    firmwareVersion: device.firmwareVersion,
    commandVersion: device.commandVersion,
    lastSensorUpdate: device.lastSensorUpdate,
    lastSeenAt: device.lastSeenAt,
    notes: device.notes,
  });
}

async function emitDeviceSideEffects(req, device) {
  emitDeviceUpdate(req, device);
  await syncDeviceNotifications(device);
}

async function ensureCustomerCapacity(customerId, { excludingDeviceId = null } = {}) {
  if (!customerId) return null;

  const customer = await customers.findById(customerId);
  if (!customer) {
    const error = new Error('ไม่พบลูกค้า');
    error.statusCode = 404;
    throw error;
  }

  const usedSlots = await devices.countForCustomer(customerId, excludingDeviceId);
  if (usedSlots >= customer.packageQty) {
    const error = new Error(`ลูกค้ารายนี้ใช้สิทธิ์ครบแล้ว (${usedSlots}/${customer.packageQty})`);
    error.statusCode = 400;
    throw error;
  }

  return customer;
}

function mapDevicePayload(body = {}) {
  const payload = {};

  if (body.serialNumber !== undefined) payload.serialNumber = normalizeString(body.serialNumber);
  if (body.name !== undefined) payload.name = normalizeString(body.name);
  if (body.location !== undefined) payload.location = normalizeString(body.location);
  if (body.hardwareId !== undefined) payload.hardwareId = normalizeString(body.hardwareId);
  if (body.hardwareModel !== undefined) payload.hardwareModel = normalizeString(body.hardwareModel, 'ESP32 Diffuser');
  if (body.mac !== undefined) payload.mac = normalizeString(body.mac).toUpperCase();
  if (body.ip !== undefined) payload.ip = normalizeString(body.ip);
  if (body.wifiSSID !== undefined) payload.wifiSSID = normalizeString(body.wifiSSID);
  if (body.wifiIP !== undefined) payload.wifiIP = normalizeString(body.wifiIP);
  if (body.btAddress !== undefined) payload.btAddress = normalizeString(body.btAddress);
  if (body.btConnected !== undefined) payload.btConnected = body.btConnected === true;
  if (body.scentName !== undefined) payload.scentName = normalizeString(body.scentName);
  if (body.notes !== undefined) payload.notes = normalizeString(body.notes);
  if (body.installedTankMl !== undefined && Number(body.installedTankMl) >= 0) payload.installedTankMl = Number(body.installedTankMl);
  if (body.level !== undefined && Number.isFinite(Number(body.level))) payload.level = Math.max(0, Math.min(100, Math.round(Number(body.level))));
  if (body.levelMl !== undefined && Number.isFinite(Number(body.levelMl))) payload.levelMl = Math.max(0, Math.round(Number(body.levelMl)));
  if (body.battery !== undefined && Number.isFinite(Number(body.battery))) payload.battery = Math.max(0, Math.min(100, Math.round(Number(body.battery))));
  if (body.batteryVoltage !== undefined && Number.isFinite(Number(body.batteryVoltage))) payload.batteryVoltage = Number(body.batteryVoltage);
  if (body.signalStrength !== undefined && Number.isFinite(Number(body.signalStrength))) payload.signalStrength = Math.round(Number(body.signalStrength));
  if (body.firmwareVersion !== undefined) payload.firmwareVersion = normalizeString(body.firmwareVersion);
  if (body.pumpOk !== undefined) payload.pumpOk = body.pumpOk === true;
  if (body.relayOk !== undefined) payload.relayOk = body.relayOk === true;
  if (body.deviceToken !== undefined) payload.deviceToken = normalizeString(body.deviceToken);
  if (body.claimCode !== undefined) payload.claimCode = normalizeString(body.claimCode);
  if (body.status !== undefined) payload.status = normalizeString(body.status, 'offline');

  if (Array.isArray(body.schedule)) {
    payload.schedule = body.schedule
      .filter((item) => item && typeof item === 'object')
      .map((item) => ({
        startTime: normalizeString(item.startTime, '08:00'),
        endTime: normalizeString(item.endTime, '18:00'),
        workSeconds: Math.max(1, Number(item.workSeconds || 30)),
        pauseSeconds: Math.max(1, Number(item.pauseSeconds || 60)),
        days: Array.isArray(item.days)
          ? Array.from({ length: 7 }, (_, index) => item.days[index] === true)
          : [false, false, false, false, false, false, false],
      }));
  }

  if (payload.levelMl !== undefined && payload.level === undefined) {
    payload.level = buildLevelPct(payload.levelMl, payload.installedTankMl ?? body.installedTankMl ?? 1000);
  }

  return payload;
}

function handleRouteError(res, error, fallbackMessage = 'เกิดข้อผิดพลาด') {
  const statusCode = error?.statusCode || 500;
  const message = error?.message || fallbackMessage;
  if (statusCode >= 500 && process.env.LOG_LEVEL !== 'error') {
    process.stderr.write(`[device-route] ${statusCode} ${message}\n`);
  }
  return res.status(statusCode).json({ message });
}

// Device-token middleware for ESP32 endpoints.
async function verifyDeviceToken(req, res, next) {
  if (process.env.DEVICE_TOKEN_REQUIRED !== 'true') return next();

  try {
    const providedToken = normalizeString(
      req.header('x-device-token') || req.body?.deviceToken || req.query?.deviceToken,
    );
    if (!providedToken) {
      return res.status(401).json({ message: 'missing device token' });
    }

    const sharedSecret = normalizeString(process.env.DEVICE_SHARED_SECRET);
    if (sharedSecret && providedToken === sharedSecret) return next();

    const raw = await devices.findRawById(req.params.id);
    if (!raw) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const expected = normalizeString(raw.device_token || raw.claim_code);
    if (!expected || providedToken !== expected) {
      return res.status(403).json({ message: 'invalid device token' });
    }
    return next();
  } catch (error) {
    return handleRouteError(res, error, 'ตรวจสอบสิทธิ์อุปกรณ์ไม่สำเร็จ');
  }
}

function parsePagination(query) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const limit = Math.min(200, Math.max(1, parseInt(query.limit, 10) || 50));
  const skip = (page - 1) * limit;
  return { page, limit, skip };
}

// GET /api/devices
router.get('/', anyRole, async (req, res) => {
  try {
    const usePagination = req.query.page !== undefined;
    const { page, limit, skip } = parsePagination(req.query);

    const result = await devices.listWithCustomers({
      customerId: req.query.customerId || null,
      status: req.query.status || null,
      search: req.query.search || null,
      skip: usePagination ? skip : 0,
      limit: usePagination ? limit : 500,
      paginated: usePagination,
    });

    if (usePagination) {
      res.json({
        data: result.data,
        pagination: {
          page,
          limit,
          total: result.total,
          pages: Math.ceil(result.total / limit),
        },
      });
    } else {
      res.json(result.data);
    }
  } catch (error) {
    handleRouteError(res, error);
  }
});

router.get('/:id', anyRole, async (req, res) => {
  try {
    const device = await devices.findById(req.params.id);
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(device);
  } catch (error) {
    handleRouteError(res, error);
  }
});

// Manual create is disabled — claim only.
router.post('/', managerUp, async (req, res) => {
  return res.status(410).json({
    message:
      'manual device creation disabled — use BLE onboarding (/api/devices/claim with hardwareId)',
    code: 'MANUAL_CREATE_DISABLED',
  });
});

// POST /api/devices/claim
router.post('/claim', managerUp, async (req, res) => {
  try {
    const deviceId = normalizeString(req.body.deviceId);
    const serialNumber = normalizeString(req.body.serialNumber);
    const customerId = normalizeString(req.body.customerId);
    const hardwareId = normalizeString(req.body.hardwareId);

    if (!deviceId && !serialNumber) {
      return res.status(400).json({ message: 'Provide deviceId or serialNumber' });
    }
    if (!customerId) {
      return res.status(400).json({ message: 'customerId is required' });
    }

    const [deviceById, deviceBySerial] = await Promise.all([
      deviceId ? devices.findById(deviceId) : null,
      serialNumber ? devices.findBySerial(serialNumber) : null,
    ]);

    if (deviceById && deviceBySerial && deviceById.id !== deviceBySerial.id) {
      return res.status(409).json({
        message: 'deviceId and serialNumber refer to different devices',
      });
    }

    let device = deviceById || deviceBySerial;
    let created = false;

    if (!device && hardwareId) {
      device = await devices.findByHardwareId(hardwareId);
    }

    if (device) {
      const currentCustomerId = device.customerId || '';
      if (customerId !== currentCustomerId) {
        await ensureCustomerCapacity(customerId, { excludingDeviceId: device.id });
      }

      const update = mapDevicePayload(req.body);
      update.customerId = customerId;
      update.provisionedAt = device.provisionedAt || new Date();
      update.lastSeenAt = new Date();

      if (deviceId && !update.hardwareId && !device.hardwareId) {
        update.hardwareId = deviceId;
      }

      const updated = await devices.updateById(device.id, update);
      return res.status(200).json({
        message: 'Device claimed successfully',
        created: false,
        device: updated,
      });
    }

    // Creating new — enforce hardware identity + capacity.
    await ensureCustomerCapacity(customerId);
    if (!serialNumber) {
      return res.status(400).json({
        message: 'serialNumber is required when creating a new device',
      });
    }
    if (!deviceId && !hardwareId && !normalizeString(req.body.mac)) {
      return res.status(400).json({
        message:
          'missing hardware identity (hardwareId / mac / deviceId) — ' +
          'use the BLE onboarding flow to claim a real device',
      });
    }

    const payload = mapDevicePayload(req.body);
    if (deviceId) payload._id = deviceId;
    payload.serialNumber = serialNumber;
    payload.customerId = customerId;
    if (deviceId && !payload.hardwareId) {
      payload.hardwareId = deviceId;
    }
    payload.status = payload.status || 'offline';
    payload.provisionedAt = new Date();
    payload.lastSeenAt = new Date();

    const newDevice = await devices.create(payload);
    created = true;

    return res.status(201).json({
      message: 'Device claimed and created',
      created,
      device: newDevice,
    });
  } catch (err) {
    if (process.env.LOG_LEVEL !== 'error') {
      process.stderr.write(`[device-route] ${err?.statusCode || 500} claim error: ${err?.message || err}\n`);
    }
    return res.status(err?.statusCode || 500).json({ message: err?.message || 'Failed to claim device' });
  }
});

// PUT /api/devices/:id
router.put('/:id', managerUp, async (req, res) => {
  try {
    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const update = mapDevicePayload(req.body);
    const incomingCustomerId = req.body.customerId !== undefined
      ? normalizeString(req.body.customerId)
      : (current.customerId || '');

    if (incomingCustomerId && incomingCustomerId !== (current.customerId || '')) {
      await ensureCustomerCapacity(incomingCustomerId, { excludingDeviceId: current.id });
      update.customerId = incomingCustomerId;
      update.provisionedAt = current.provisionedAt || new Date();
    }

    const updated = await devices.updateById(current.id, update);
    await emitDeviceSideEffects(req, updated);
    res.json(updated);
  } catch (error) {
    handleRouteError(res, error, 'อัปเดตเครื่องไม่สำเร็จ');
  }
});

// PUT /api/devices/:id/status  — app-issued on/off
router.put('/:id/status', anyRole, async (req, res) => {
  try {
    const { isOn } = req.body;
    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const updated = await devices.updateById(current.id, {
      isOn: !!isOn,
      commandVersion: (current.commandVersion || 0) + 1,
      lastCommandAt: new Date(),
    });
    await emitDeviceSideEffects(req, updated);
    res.json(updated);
  } catch (error) {
    handleRouteError(res, error, 'เปลี่ยนสถานะไม่สำเร็จ');
  }
});

// PUT /api/devices/:id/schedule
router.put('/:id/schedule', anyRole, async (req, res) => {
  try {
    const schedule = Array.isArray(req.body.schedule)
      ? mapDevicePayload({ schedule: req.body.schedule }).schedule
      : null;
    if (!schedule) {
      return res.status(400).json({ message: 'กรอก schedule array' });
    }

    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const updated = await devices.updateById(current.id, {
      schedule,
      commandVersion: (current.commandVersion || 0) + 1,
      lastCommandAt: new Date(),
    });
    await emitDeviceSideEffects(req, updated);
    res.json(updated);
  } catch (error) {
    handleRouteError(res, error, 'บันทึกตารางเวลาไม่สำเร็จ');
  }
});

// PUT /api/devices/:id/assign-customer
router.put('/:id/assign-customer', managerUp, async (req, res) => {
  try {
    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const customerId = normalizeString(req.body.customerId);
    if (customerId && customerId !== (current.customerId || '')) {
      await ensureCustomerCapacity(customerId, { excludingDeviceId: current.id });
    }

    const patch = { customerId: customerId || null };
    if (req.body.location !== undefined) patch.location = normalizeString(req.body.location);
    if (customerId) patch.provisionedAt = current.provisionedAt || new Date();

    const updated = await devices.updateById(current.id, patch);
    await emitDeviceSideEffects(req, updated);
    res.json(updated);
  } catch (error) {
    handleRouteError(res, error, 'ผูกลูกค้าไม่สำเร็จ');
  }
});

// ═══════════════ ESP32 endpoints ═══════════════

// GET /api/devices/:id/state
router.get('/:id/state', verifyDeviceToken, async (req, res) => {
  try {
    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const patch = { lastSeenAt: new Date() };
    if (current.status !== 'online') patch.status = 'online';
    const updated = Object.keys(patch).length
      ? await devices.updateById(current.id, patch)
      : current;
    if (patch.status) await emitDeviceSideEffects(req, updated);

    res.json({
      isOn: updated.isOn,
      level: updated.level,
      levelMl: updated.levelMl,
      schedule: updated.schedule,
      status: updated.status,
      wifiSSID: updated.wifiSSID,
      commandVersion: updated.commandVersion || 0,
      lastCommandAt: updated.lastCommandAt,
    });
  } catch (error) {
    handleRouteError(res, error, 'ดึงสถานะเครื่องไม่สำเร็จ');
  }
});

// PUT /api/devices/:id/sensor
router.put('/:id/sensor', verifyDeviceToken, async (req, res) => {
  try {
    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const update = mapDevicePayload(req.body);
    update.lastSensorUpdate = new Date();
    update.lastSeenAt = new Date();
    update.status = update.status || 'online';
    delete update.customerId;   // sensor payloads cannot reassign customers

    const updated = await devices.updateById(current.id, update);
    await emitDeviceSideEffects(req, updated);

    res.json({
      message: 'OK',
      level: updated.level,
      levelMl: updated.levelMl,
      commandVersion: updated.commandVersion || 0,
      isOn: updated.isOn,
    });
  } catch (error) {
    handleRouteError(res, error, 'รับข้อมูลเซนเซอร์ไม่สำเร็จ');
  }
});

// PUT /api/devices/:id/hw-toggle
router.put('/:id/hw-toggle', verifyDeviceToken, async (req, res) => {
  try {
    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const updated = await devices.updateById(current.id, {
      isOn: !!req.body.isOn,
      status: 'online',
      lastSeenAt: new Date(),
    });
    await emitDeviceSideEffects(req, updated);
    res.json({ message: 'OK', isOn: updated.isOn, commandVersion: updated.commandVersion || 0 });
  } catch (error) {
    handleRouteError(res, error, 'สลับสถานะจากเครื่องไม่สำเร็จ');
  }
});

// PUT /api/devices/:id/schedule-from-hw
router.put('/:id/schedule-from-hw', verifyDeviceToken, async (req, res) => {
  try {
    const schedule = Array.isArray(req.body.schedule)
      ? mapDevicePayload({ schedule: req.body.schedule }).schedule
      : null;
    if (!schedule) return res.status(400).json({ message: 'กรอก schedule array' });

    const current = await devices.findById(req.params.id);
    if (!current) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const updated = await devices.updateById(current.id, {
      schedule,
      status: 'online',
      lastSeenAt: new Date(),
    });
    await emitDeviceSideEffects(req, updated);
    res.json({ message: 'OK', schedules: updated.schedule.length, commandVersion: updated.commandVersion || 0 });
  } catch (error) {
    handleRouteError(res, error, 'บันทึกตารางจากเครื่องไม่สำเร็จ');
  }
});

// DELETE /api/devices/:id
router.delete('/:id', managerUp, async (req, res) => {
  try {
    const ok = await devices.deleteById(req.params.id);
    if (!ok) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    const io = req.app.get('io');
    if (io) io.emit('device:removed', { id: req.params.id });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    handleRouteError(res, error, 'ลบเครื่องไม่สำเร็จ');
  }
});

module.exports = router;
