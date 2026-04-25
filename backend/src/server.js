// src/server.js — v6.0.0 (Apr 2026)
// ─────────────────────────────────────────────────────────────
// Changes vs v5.2.5:
//   • Persistence moved from MongoDB/Mongoose to PostgreSQL (pg).
//     All routes now talk to src/repositories/*, which map rows to
//     the exact camelCase shape the Flutter app and firmware expect.
//   • Firebase Admin is initialized here so push is available to
//     the alert pipeline. If no credential is configured, push
//     becomes a no-op and the rest of the backend keeps running.
//   • Inline /api/notifications and /api/search handlers rewritten
//     against the repositories. Contract is identical to v5.2.5.
//   • Offline monitor now uses a single UPDATE ... RETURNING to
//     flip stale devices and collect them for the grace queue.
//
// Preserved behaviour:
//   • CORS allowlist from env, helmet, login rate-limit.
//   • trust proxy = 1 for Render / nginx.
//   • Socket.IO JWT handshake + device:toggle event.
//   • Device-token middleware for ESP32 endpoints.
//   • Offline grace + dedupe for notifications.
// ─────────────────────────────────────────────────────────────
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const express = require('express');
const cors = require('cors');
const http = require('http');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { Server } = require('socket.io');

const { connectDB } = require('./config/db');
const devicesRepo = require('./repositories/devices');
const notificationsRepo = require('./repositories/notifications');
const customersRepo = require('./repositories/customers');
const { syncDeviceNotifications } = require('./utils/device-notifications');
const fcmAdmin = require('./fcm/admin');
const { verify, SECRET } = require('./middleware/auth');

// ─── Logger ──────────────────────────────────────────────────
const LOG_LEVEL = (process.env.LOG_LEVEL || 'info').toLowerCase();
const LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const shouldLog = (level) => (LEVELS[level] ?? 0) <= (LEVELS[LOG_LEVEL] ?? 2);
const log = {
  error: (...args) => shouldLog('error') && process.stderr.write(`[ERROR] ${args.join(' ')}\n`),
  warn:  (...args) => shouldLog('warn')  && process.stderr.write(`[WARN] ${args.join(' ')}\n`),
  info:  (...args) => shouldLog('info')  && process.stdout.write(`[INFO] ${args.join(' ')}\n`),
  debug: (...args) => shouldLog('debug') && process.stdout.write(`[DEBUG] ${args.join(' ')}\n`),
};

// ─── Timing / offline detection ──────────────────────────────
const OFFLINE_THRESHOLD_MS   = Number(process.env.DEVICE_OFFLINE_THRESHOLD_MS || 180000);
const OFFLINE_GRACE_MS       = Number(process.env.OFFLINE_NOTIFICATION_GRACE_MS || 30000);
const OFFLINE_MONITOR_TICK_MS = 30000;

// ─── CORS ────────────────────────────────────────────────────
const NODE_ENV = (process.env.NODE_ENV || 'development').toLowerCase();
const IS_PROD = NODE_ENV === 'production';
const CORS_ALLOWED_ORIGINS = (process.env.CORS_ALLOWED_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

if (IS_PROD && CORS_ALLOWED_ORIGINS.length === 0) {
  log.warn(
    'NODE_ENV=production but CORS_ALLOWED_ORIGINS is empty. ' +
    'All browser origins will be REJECTED. Set CORS_ALLOWED_ORIGINS ' +
    'in the environment (comma-separated) to permit your web/app hosts.'
  );
}

const corsOriginFn = (origin, cb) => {
  if (!origin) return cb(null, true);
  if (!IS_PROD && CORS_ALLOWED_ORIGINS.length === 0) return cb(null, true);
  if (CORS_ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
  return cb(new Error(`CORS: origin not allowed: ${origin}`));
};

// ─── App + IO ────────────────────────────────────────────────
const app = express();
app.set('trust proxy', 1);

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: corsOriginFn,
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    credentials: true,
  },
});
app.set('io', io);

io.use((socket, next) => {
  const token =
    socket.handshake.auth?.token ||
    socket.handshake.headers?.authorization?.replace(/^Bearer\s+/i, '');
  if (!token) return next(new Error('unauthorized: missing token'));
  try {
    const payload = jwt.verify(token, SECRET);
    socket.data.user = {
      id: String(payload.id),
      role: payload.role,
      email: payload.email,
      name: payload.name,
    };
    return next();
  } catch (err) {
    return next(new Error('unauthorized: invalid token'));
  }
});

// ─── DB + FCM ────────────────────────────────────────────────
(async () => {
  try {
    await connectDB();
  } catch (err) {
    log.error('Postgres connect failed:', err.message);
    process.exit(1);
  }
  fcmAdmin.init();
})();

// ─── Middleware ──────────────────────────────────────────────
app.use(helmet({
  crossOriginResourcePolicy: { policy: 'cross-origin' },
  contentSecurityPolicy: false,
}));
app.use(cors({ origin: corsOriginFn, credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'พยายามเข้าสู่ระบบบ่อยเกินไป กรุณารอ 15 นาที' },
});
app.use('/api/auth/login', loginLimiter);

// ─── Routes ──────────────────────────────────────────────────
app.use('/api/auth',         require('./routes/auth'));
app.use('/api/users',        require('./routes/users'));
app.use('/api/devices',      require('./routes/devices'));
app.use('/api/customers',    require('./routes/customers'));
app.use('/api/service-logs', require('./routes/service-logs'));
app.use('/api/stats',        require('./routes/stats'));

// ─── Notifications (per-user read state) ────────────────────
app.get('/api/notifications', verify, async (req, res) => {
  try {
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const list = await notificationsRepo.listForUser({
      userId: req.user.id,
      role: req.user.role,
      limit,
    });
    res.json(list);
  } catch (error) {
    log.error('Notification list error:', error.message);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

app.put('/api/notifications/read-all', verify, async (req, res) => {
  try {
    await notificationsRepo.markAllRead({
      userId: req.user.id,
      role: req.user.role,
    });
    res.json({ message: 'OK' });
  } catch (error) {
    log.error('Notification read-all error:', error.message);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

app.put('/api/notifications/:id/read', verify, async (req, res) => {
  try {
    const found = await notificationsRepo.findByIdForUser(req.params.id, {
      userId: req.user.id,
      role: req.user.role,
    });
    if (!found) return res.status(404).json({ message: 'ไม่พบการแจ้งเตือน' });
    await notificationsRepo.markRead(req.params.id, req.user.id);
    res.json({ message: 'OK' });
  } catch (error) {
    log.error('Notification read error:', error.message);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

app.delete('/api/notifications', verify, async (req, res) => {
  try {
    await notificationsRepo.deleteAllForUser({
      userId: req.user.id,
      role: req.user.role,
    });
    res.json({ message: 'OK' });
  } catch (error) {
    log.error('Notification delete-all error:', error.message);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

app.delete('/api/notifications/:id', verify, async (req, res) => {
  try {
    const ok = await notificationsRepo.deleteForUser(req.params.id, {
      userId: req.user.id,
      role: req.user.role,
    });
    if (!ok) return res.status(404).json({ message: 'ไม่พบการแจ้งเตือน' });
    res.json({ message: 'OK' });
  } catch (error) {
    log.error('Notification delete error:', error.message);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// ─── Global search ───────────────────────────────────────────
app.get('/api/search', verify, async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) return res.json({ customers: [], devices: [] });

    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const [customerRows, devicesFound] = await Promise.all([
      customersRepo.listSearch(q),
      devicesRepo.searchGlobal(q, limit * 2),
    ]);

    const statsMap = await customersRepo.buildStatsMap();
    res.json({
      customers: customerRows.slice(0, limit).map((row) =>
        customersRepo.mapCustomer(row, statsMap.get(row.id) || {})),
      devices: devicesFound,
    });
  } catch (error) {
    log.error('Search error:', error.message);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// ─── Health ──────────────────────────────────────────────────
app.get('/health', async (req, res) => {
  let onlineDevices = 0;
  try { onlineDevices = await devicesRepo.countOnline(); } catch (_) {}
  res.json({
    status: 'OK',
    version: '6.0.0',
    nodeEnv: NODE_ENV,
    db: 'PostgreSQL',
    ws: 'Socket.IO',
    fcm: fcmAdmin.isReady() ? 'ready' : 'disabled',
    deviceTokenRequired: process.env.DEVICE_TOKEN_REQUIRED === 'true',
    socketAuth: 'jwt-required',
    corsOriginsConfigured: CORS_ALLOWED_ORIGINS.length,
    offlineThresholdMs: OFFLINE_THRESHOLD_MS,
    offlineGraceMs: OFFLINE_GRACE_MS,
    onlineDevices,
    uptimeSeconds: Math.round(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

// ─── Socket.IO ───────────────────────────────────────────────
io.on('connection', (socket) => {
  const authUser = socket.data.user;
  log.debug(`Client connected: ${socket.id} (user=${authUser.email} role=${authUser.role})`);

  socket.join(`role:${authUser.role}`);
  socket.join(`user:${authUser.id}`);

  socket.on('join', () => {
    socket.join(`role:${authUser.role}`);
    socket.join(`user:${authUser.id}`);
  });

  socket.on('device:toggle', async (data) => {
    try {
      if (!['admin', 'manager', 'technician'].includes(authUser.role)) {
        log.warn(`device:toggle rejected — user ${authUser.email} has role ${authUser.role}`);
        return;
      }
      const { deviceId, isOn } = data || {};
      if (!deviceId) return;
      const current = await devicesRepo.findById(deviceId);
      if (!current) return;

      const updated = await devicesRepo.updateById(current.id, {
        isOn: !!isOn,
        commandVersion: (current.commandVersion || 0) + 1,
        lastCommandAt: new Date(),
      });
      io.emit('device:updated', {
        id: updated.id,
        isOn: updated.isOn,
        level: updated.level,
        levelMl: updated.levelMl,
        battery: updated.battery,
        status: updated.status,
        commandVersion: updated.commandVersion,
      });
    } catch (error) {
      log.error('Socket device:toggle error:', error.message);
    }
  });

  socket.on('disconnect', () => {
    log.debug(`Client disconnected: ${socket.id}`);
  });
});

// ─── Offline device monitor ──────────────────────────────────
const pendingOfflineNotifications = new Map();
let offlineMonitorRunning = false;

setInterval(async () => {
  if (offlineMonitorRunning) return;
  offlineMonitorRunning = true;
  try {
    const cutoff = new Date(Date.now() - OFFLINE_THRESHOLD_MS);
    const flipped = await devicesRepo.markStaleOffline(cutoff);

    for (const row of flipped) {
      io.emit('device:updated', {
        id: row.id,
        status: 'offline',
        isOn: row.isOn,
        level: row.level,
        levelMl: row.levelMl,
        battery: row.battery,
      });
      if (!pendingOfflineNotifications.has(row.id)) {
        pendingOfflineNotifications.set(row.id, Date.now());
        log.debug(`Device ${row.id} offline — notification queued (grace ${OFFLINE_GRACE_MS}ms)`);
      }
    }

    if (flipped.length > 0) {
      log.info(`Offline monitor: ${flipped.length} device(s) marked offline`);
    }

    for (const [deviceId, queuedAt] of pendingOfflineNotifications) {
      if (Date.now() - queuedAt < OFFLINE_GRACE_MS) continue;
      pendingOfflineNotifications.delete(deviceId);
      try {
        const device = await devicesRepo.findById(deviceId);
        if (!device) continue;
        if (device.status !== 'offline') {
          log.debug(`Device ${deviceId} recovered during grace — notification skipped`);
          continue;
        }
        await syncDeviceNotifications(device);
        log.info(`Offline notification sent for device ${deviceId} after grace period`);
      } catch (err) {
        log.error(`Pending offline notification error for ${deviceId}:`, err.message);
      }
    }
  } catch (error) {
    log.error('Offline monitor error:', error.message);
  } finally {
    offlineMonitorRunning = false;
  }
}, OFFLINE_MONITOR_TICK_MS);

// ─── 404 / error handlers ────────────────────────────────────
app.use((req, res) => res.status(404).json({ message: 'Route not found', code: 'NOT_FOUND' }));
app.use((err, req, res, _next) => {
  log.error(err.stack || err.message || err);
  res.status(500).json({ message: 'Something went wrong!', code: 'SERVER_ERROR' });
});

// ─── Listen ──────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  log.info(`Scent & Sense Backend v6.0.0`);
  log.info(`http://0.0.0.0:${PORT} (NODE_ENV=${NODE_ENV})`);
  log.info('Socket.IO ready (JWT required on handshake)');
  log.info(`DB: PostgreSQL`);
  log.info(`FCM: ${fcmAdmin.isReady() ? 'ready' : 'disabled (no credential)'}`);
  log.info(`Device token auth: ${process.env.DEVICE_TOKEN_REQUIRED === 'true' ? 'ENABLED' : 'DISABLED'}`);
  log.info(`CORS allowlist: ${CORS_ALLOWED_ORIGINS.length === 0 ? '(empty — dev only)' : CORS_ALLOWED_ORIGINS.join(', ')}`);
  log.info(`Offline threshold: ${OFFLINE_THRESHOLD_MS}ms · grace: ${OFFLINE_GRACE_MS}ms · tick: ${OFFLINE_MONITOR_TICK_MS}ms`);
});
