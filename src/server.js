// server.js — Scent & Sense Backend v3.1 (MongoDB + Socket.IO)
require('dotenv').config();
const express   = require('express');
const cors      = require('cors');
const http      = require('http');
const { Server } = require('socket.io');
const connectDB = require('./config/db');

const app    = express();
const server = http.createServer(app);

// ★ NEW: Socket.IO
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST', 'PUT', 'DELETE'] },
});

// เก็บ io ไว้ใน app เพื่อให้ routes เข้าถึงได้
app.set('io', io);

// Connect MongoDB ก่อนเปิด Server
connectDB();

app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// ─── Routes ─────────────────────────────────────────────────
app.use('/api/auth',         require('./routes/auth'));
app.use('/api/users',        require('./routes/users'));
app.use('/api/devices',      require('./routes/devices'));
app.use('/api/customers',    require('./routes/customers'));
app.use('/api/service-logs', require('./routes/service-logs'));
app.use('/api/stats',        require('./routes/stats'));

// ─── Notifications ──────────────────────────────────────────
const { verify }  = require('./middleware/auth');
const Notification = require('./models/Notification');

app.get('/api/notifications', verify, async (req, res) => {
  try {
    const query = req.user.role === 'admin' ? {} : { targetRoles: req.user.role };
    const list  = await Notification.find(query).sort({ createdAt: -1 }).limit(50);
    res.json(list.map(n => ({ ...n.toObject(), id: n._id.toString() })));
  } catch {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

app.put('/api/notifications/read-all', verify, async (req, res) => {
  await Notification.updateMany({}, { isRead: true });
  res.json({ message: 'OK' });
});

app.put('/api/notifications/:id/read', verify, async (req, res) => {
  await Notification.findByIdAndUpdate(req.params.id, { isRead: true });
  res.json({ message: 'OK' });
});

// ─── Search ─────────────────────────────────────────────────
const Device   = require('./models/Device');
const Customer = require('./models/Customer');

app.get('/api/search', verify, async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q) return res.json({ customers: [], devices: [] });

    const regex = new RegExp(q, 'i');
    const [customers, devices] = await Promise.all([
      Customer.find({ $or: [{ name: regex }, { address: regex }] }),
      Device.find({ $or: [{ name: regex }, { serialNumber: regex }, { location: regex }, { wifiSSID: regex }] }),
    ]);

    const enrichedDevices = await Promise.all(devices.map(async d => {
      const c = d.customerId ? await Customer.findById(d.customerId) : null;
      return { ...d.toObject(), id: d._id.toString(), customerId: d.customerId?.toString() || null, customerName: c?.name || '' };
    }));

    res.json({
      customers: customers.map(c => ({ ...c.toObject(), id: c._id.toString() })),
      devices:   enrichedDevices,
    });
  } catch {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// ─── Health ─────────────────────────────────────────────────
app.get('/test',   (req, res) => res.json({ message: 'Scent & Sense Backend v3.1 (MongoDB + Socket.IO) ✅' }));
app.get('/health', (req, res) => res.json({ status: 'OK', version: '3.1.0', db: 'MongoDB', ws: 'Socket.IO', timestamp: new Date().toISOString() }));

// ─── Socket.IO Events ──────────────────────────────────────
io.on('connection', (socket) => {
  console.log(`🔌 Client connected: ${socket.id}`);

  // Client ส่ง join room ตาม role
  socket.on('join', (data) => {
    if (data?.role) {
      socket.join(`role:${data.role}`);
      console.log(`  → ${socket.id} joined role:${data.role}`);
    }
    if (data?.userId) {
      socket.join(`user:${data.userId}`);
    }
  });

  // Client สั่ง toggle device
  socket.on('device:toggle', async (data) => {
    try {
      const { deviceId, isOn } = data;
      const device = await Device.findByIdAndUpdate(deviceId, { isOn }, { new: true });
      if (device) {
        io.emit('device:updated', {
          id: device._id.toString(),
          isOn: device.isOn,
          level: device.level,
          levelMl: device.levelMl,
          status: device.status,
        });
      }
    } catch (err) {
      console.error('Socket device:toggle error:', err);
    }
  });

  socket.on('disconnect', () => {
    console.log(`🔌 Client disconnected: ${socket.id}`);
  });
});

// ─── Error Handlers ─────────────────────────────────────────
app.use((req, res) => res.status(404).json({ message: 'Route not found' }));
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ message: 'Something went wrong!' });
});

// ★ CHANGED: ใช้ server.listen แทน app.listen เพื่อให้ Socket.IO ทำงาน
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Scent & Sense Backend v3.1 (MongoDB + Socket.IO)`);
  console.log(`🔗 http://0.0.0.0:${PORT}`);
  console.log(`📦 DB: MongoDB Atlas`);
  console.log(`🔌 WebSocket: Socket.IO ready`);
});
