// routes/service-logs.js
const router     = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const ServiceLog = require('../models/ServiceLog');
const Device     = require('../models/Device');
const User       = require('../models/User');
const Customer   = require('../models/Customer');

// Helper: เพิ่ม deviceName, customerName, technicianName
const enrich = async (log) => {
  const obj = log.toObject ? log.toObject() : log;
  const [device, tech] = await Promise.all([
    Device.findById(obj.deviceId),
    User.findById(obj.technicianId),
  ]);
  const customer = device?.customerId ? await Customer.findById(device.customerId) : null;
  return {
    ...obj,
    id:             obj._id.toString(),
    deviceId:       obj.deviceId?.toString()     || '',
    technicianId:   obj.technicianId?.toString() || '',
    deviceName:     device?.name                 || '',
    deviceSerial:   device?.serialNumber         || '',
    customerName:   customer?.name               || '',
    technicianName: tech?.name                   || '',
  };
};

// GET /api/service-logs
router.get('/', anyRole, async (req, res) => {
  try {
    const query = {};
    if (req.user.role === 'technician') query.technicianId = req.user.id;
    if (req.query.deviceId) query.deviceId = req.query.deviceId;
    if (req.query.customerId) {
      const devices = await Device.find({ customerId: req.query.customerId });
      query.deviceId = { $in: devices.map(d => d._id) };
    }

    const logs = await ServiceLog.find(query).sort({ createdAt: -1 });
    const enriched = await Promise.all(logs.map(enrich));
    res.json(enriched);
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/service-logs
router.post('/', anyRole, async (req, res) => {
  try {
    const { deviceId, type, description, notes, photos } = req.body;
    if (!deviceId || !type)
      return res.status(400).json({ message: 'กรอก deviceId และ type' });

    const device = await Device.findById(deviceId);
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    const validTypes = ['refill', 'repair', 'inspection', 'installation', 'uninstall', 'other'];
    if (!validTypes.includes(type))
      return res.status(400).json({ message: `type ต้องเป็น: ${validTypes.join(', ')}` });

    const log = new ServiceLog({
      deviceId,
      technicianId: req.user.id,
      type,
      description: description || '',
      notes:       notes       || '',
      photos:      photos      || [],
    });
    await log.save();
    res.status(201).json(await enrich(log));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// GET /api/service-logs/export
router.get('/export', managerUp, async (req, res) => {
  try {
    const query = {};
    const { customerId, startDate, endDate } = req.query;

    if (customerId) {
      const devices = await Device.find({ customerId });
      query.deviceId = { $in: devices.map(d => d._id) };
    }
    if (startDate) query.createdAt = { ...query.createdAt, $gte: new Date(startDate) };
    if (endDate)   query.createdAt = { ...query.createdAt, $lte: new Date(endDate) };

    const logs     = await ServiceLog.find(query).sort({ createdAt: -1 });
    const enriched = await Promise.all(logs.map(enrich));
    const customer = customerId ? await Customer.findById(customerId) : null;

    res.json({
      reportTitle:  customer ? `รายงานเซอร์วิส - ${customer.name}` : 'รายงานเซอร์วิสทั้งหมด',
      generatedAt:  new Date().toISOString(),
      totalRecords: enriched.length,
      records:      enriched,
    });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
