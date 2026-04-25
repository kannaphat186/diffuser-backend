// src/routes/stats.js — v6.0.0
const router = require('express').Router();
const { managerUp } = require('../middleware/auth');
const devices = require('../repositories/devices');
const customers = require('../repositories/customers');
const serviceLogs = require('../repositories/service_logs');

router.get('/', managerUp, async (req, res) => {
  try {
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const sevenDaysAgo = new Date(Date.now() - 6 * 24 * 60 * 60 * 1000);

    const [deviceSummary, totalCustomers, totalServiceLogs, recentLogsCount, logsByType, fragrancePerDevice, dailyAgg] = await Promise.all([
      devices.summary(),
      customers.countAll(),
      serviceLogs.countAll(),
      serviceLogs.countSince(thirtyDaysAgo),
      serviceLogs.countByTypeSince(thirtyDaysAgo),
      devices.levelPerDevice(),
      serviceLogs.dailyCountsSince(sevenDaysAgo),
    ]);

    const dailyMap = new Map((dailyAgg || []).map((r) => [r.day, r.count]));
    const daily = [];
    for (let i = 6; i >= 0; i -= 1) {
      const date = new Date(Date.now() - i * 24 * 60 * 60 * 1000);
      const dayStr = date.toISOString().split('T')[0];
      daily.push({ date: dayStr, count: dailyMap.get(dayStr) || 0 });
    }

    res.json({
      totalDevices: deviceSummary.total_devices || 0,
      onlineDevices: deviceSummary.online_devices || 0,
      activeDevices: deviceSummary.active_devices || 0,
      alertDevices: deviceSummary.alert_devices || 0,
      avgLevel: Math.round(deviceSummary.avg_level || 0),
      totalCustomers,
      totalServiceLogs,
      recentServiceLogs: recentLogsCount,
      logsByType,
      fragrancePerDevice: fragrancePerDevice.map((d) => ({
        id: d.id,
        name: d.name || d.serial_number,
        level: d.level,
        levelMl: d.level_ml ?? (d.level != null ? d.level * 10 : 0),
      })),
      daily,
    });
  } catch (error) {
    process.stderr.write(`[stats] error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
