// src/routes/service-logs.js — v6.0.0
const router = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const serviceLogs = require('../repositories/service_logs');
const devices = require('../repositories/devices');
const customers = require('../repositories/customers');

router.get('/', anyRole, async (req, res) => {
  try {
    const filters = {};
    if (req.user.role === 'technician') filters.technicianId = req.user.id;
    if (req.query.deviceId) filters.deviceId = req.query.deviceId;
    if (req.query.customerId) filters.customerId = req.query.customerId;

    const logs = await serviceLogs.listEnriched(filters);
    res.json(logs);
  } catch (error) {
    process.stderr.write(`[service-logs] list error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.post('/', anyRole, async (req, res) => {
  try {
    const { deviceId, type, description, notes, photos } = req.body;
    if (!deviceId || !type) {
      return res.status(400).json({ message: 'กรอก deviceId และ type' });
    }

    const device = await devices.findById(deviceId);
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const log = await serviceLogs.create({
      deviceId,
      technicianId: req.user.id,
      type,
      description: description || '',
      notes: notes || '',
      photos: Array.isArray(photos) ? photos : [],
    });
    res.status(201).json(log);
  } catch (error) {
    if (error.statusCode === 400) {
      return res.status(400).json({ message: error.message });
    }
    process.stderr.write(`[service-logs] create error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.get('/export', managerUp, async (req, res) => {
  try {
    const { customerId, startDate, endDate } = req.query;
    const filters = {};
    if (customerId) filters.customerId = customerId;
    if (startDate) filters.startDate = new Date(startDate);
    if (endDate) filters.endDate = new Date(endDate);

    const logs = await serviceLogs.listEnriched(filters);
    const customer = customerId ? await customers.findById(customerId) : null;

    res.json({
      reportTitle: customer ? `รายงานเซอร์วิส - ${customer.name}` : 'รายงานเซอร์วิสทั้งหมด',
      generatedAt: new Date().toISOString(),
      totalRecords: logs.length,
      records: logs,
    });
  } catch (error) {
    process.stderr.write(`[service-logs] export error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
