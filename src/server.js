require('dotenv').config();
const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Routes
const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');
const devicesRoutes = require('./routes/devices');
const customersRoutes = require('./routes/customers');
const serviceLogsRoutes = require('./routes/service-logs');

app.use('/api/auth', authRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/devices', devicesRoutes);
app.use('/api/customers', customersRoutes);
app.use('/api/service-logs', serviceLogsRoutes);

// Notifications
const { notifications } = require('./database');
const { verify } = require('./middleware/auth');

app.get('/api/notifications', verify, (req, res) => {
  const result = notifications
    .filter(n => req.user.role === 'admin' || n.targetRoles?.includes(req.user.role))
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
    .slice(0, 50);
  res.json(result);
});
app.put('/api/notifications/:id/read', verify, (req, res) => {
  const n = notifications.find(n => n.id === req.params.id);
  if (n) n.isRead = true;
  res.json({ message: 'OK' });
});
app.put('/api/notifications/read-all', verify, (req, res) => {
  notifications.forEach(n => n.isRead = true);
  res.json({ message: 'OK' });
});

// Search
const { devices, customers } = require('./database');
app.get('/api/search', verify, (req, res) => {
  const q = (req.query.q || '').toLowerCase();
  if (!q) return res.json({ customers: [], devices: [] });
  const matchedCustomers = customers.filter(c =>
    c.name.toLowerCase().includes(q) || c.address.toLowerCase().includes(q));
  const matchedDevices = devices.filter(d =>
    d.name.toLowerCase().includes(q) || d.serialNumber.toLowerCase().includes(q) ||
    d.location.toLowerCase().includes(q) || d.wifiSSID.toLowerCase().includes(q));
  res.json({
    customers: matchedCustomers,
    devices: matchedDevices.map(d => ({
      ...d, customerName: d.customerId ? customers.find(c => c.id === d.customerId)?.name || '' : ''
    }))
  });
});

// Health
app.get('/test', (req, res) => res.json({ message: 'Scent & Sense Backend v1.0 OK' }));
app.get('/health', (req, res) => res.json({ status: 'OK', version: '1.0.0', timestamp: new Date().toISOString() }));

app.use((req, res) => res.status(404).json({ message: 'Route not found' }));
app.use((err, req, res, next) => { console.error(err.stack); res.status(500).json({ message: 'Something went wrong!' }); });

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Scent & Sense Backend v1.0`);
  console.log(`📍 http://0.0.0.0:${PORT}`);
  console.log(`🔑 Test accounts:`);
  console.log(`   Admin:      admin@scentandsense.com / password`);
  console.log(`   Manager:    manager@scentandsense.com / password`);
  console.log(`   Technician: tech@scentandsense.com / password`);
});
