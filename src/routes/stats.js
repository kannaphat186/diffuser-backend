// routes/stats.js — ★ NEW: Stats API จริง
const router     = require('express').Router();
const { anyRole } = require('../middleware/auth');
const Device     = require('../models/Device');
const Customer   = require('../models/Customer');
const ServiceLog = require('../models/ServiceLog');

// GET /api/stats
router.get('/', anyRole, async (req, res) => {
  try {
    const [devices, customers, logs] = await Promise.all([
      Device.find(),
      Customer.find(),
      ServiceLog.find().sort({ createdAt: -1 }),
    ]);

    const totalDevices  = devices.length;
    const onlineDevices = devices.filter(d => d.status === 'online').length;
    const activeDevices = devices.filter(d => d.isOn).length;
    const alertDevices  = devices.filter(d => d.level < 20 || !d.pumpOk || !d.relayOk).length;
    const avgLevel      = totalDevices > 0
      ? Math.round(devices.reduce((sum, d) => sum + d.level, 0) / totalDevices)
      : 0;

    // สถิติ Service Logs ใน 30 วัน
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const recentLogs = logs.filter(l => new Date(l.createdAt) >= thirtyDaysAgo);
    const logsByType = {};
    for (const l of recentLogs) {
      logsByType[l.type] = (logsByType[l.type] || 0) + 1;
    }

    // น้ำหอมแต่ละเครื่อง
    const fragrancePerDevice = devices.map(d => ({
      id: d._id.toString(),
      name: d.name || d.serialNumber,
      level: d.level,
      levelMl: d.levelMl ?? d.level * 10,
    }));

    // ข้อมูลรายวัน (7 วัน)
    const daily = [];
    for (let i = 6; i >= 0; i--) {
      const date = new Date(Date.now() - i * 24 * 60 * 60 * 1000);
      const dayStr = date.toISOString().split('T')[0];
      const count = logs.filter(l => {
        const ld = new Date(l.createdAt).toISOString().split('T')[0];
        return ld === dayStr;
      }).length;
      daily.push({ date: dayStr, count });
    }

    res.json({
      totalDevices,
      onlineDevices,
      activeDevices,
      alertDevices,
      avgLevel,
      totalCustomers: customers.length,
      totalServiceLogs: logs.length,
      recentServiceLogs: recentLogs.length,
      logsByType,
      fragrancePerDevice,
      daily,
    });
  } catch (error) {
    console.error('Stats error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
