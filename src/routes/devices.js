// routes/devices.js — v3.1 เพิ่ม Socket.IO emit เมื่อ device เปลี่ยน
const router   = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const Device   = require('../models/Device');
const Customer = require('../models/Customer');

const fmt = async (d, customers) => {
  const obj = d.toObject ? d.toObject() : d;
  let customerName = '';
  if (obj.customerId) {
    const c = customers
      ? customers.find(c => c._id.toString() === obj.customerId?.toString())
      : await Customer.findById(obj.customerId);
    customerName = c?.name || '';
  }
  return {
    ...obj,
    id: obj._id.toString(),
    customerId: obj.customerId?.toString() || null,
    customerName,
    levelMl: obj.levelMl ?? null,
  };
};

// Helper: emit device update via Socket.IO
const emitDeviceUpdate = (req, device) => {
  const io = req.app.get('io');
  if (io) {
    io.emit('device:updated', {
      id: device._id.toString(),
      isOn: device.isOn,
      level: device.level,
      levelMl: device.levelMl,
      status: device.status,
      pumpOk: device.pumpOk,
      relayOk: device.relayOk,
    });
  }
};

// GET /api/devices
router.get('/', anyRole, async (req, res) => {
  try {
    const query = {};
    if (req.query.customerId) query.customerId = req.query.customerId;
    if (req.query.search) {
      const regex = new RegExp(req.query.search, 'i');
      query.$or = [{ name: regex }, { serialNumber: regex }, { location: regex }];
    }
    const [devices, customers] = await Promise.all([
      Device.find(query).sort({ createdAt: -1 }),
      Customer.find(),
    ]);
    const result = await Promise.all(devices.map(d => fmt(d, customers)));
    res.json(result);
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// GET /api/devices/:id
router.get('/:id', anyRole, async (req, res) => {
  try {
    const device = await Device.findById(req.params.id);
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/devices
router.post('/', managerUp, async (req, res) => {
  try {
    const { serialNumber, name, location, customerId, level, wifiSSID } = req.body;
    if (!serialNumber)
      return res.status(400).json({ message: 'กรอก serialNumber' });

    const existing = await Device.findOne({ serialNumber });
    if (existing)
      return res.status(400).json({ message: 'Serial number นี้มีในระบบแล้ว' });

    const device = new Device({
      serialNumber, name: name || '', location: location || '',
      customerId: customerId || null, level: level ?? 100, wifiSSID: wifiSSID || '',
    });
    await device.save();
    res.status(201).json(await fmt(device));
  } catch (error) {
    console.error('Create device error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id
router.put('/:id', anyRole, async (req, res) => {
  try {
    const device = await Device.findByIdAndUpdate(req.params.id, req.body, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    emitDeviceUpdate(req, device);
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/status — เปิด/ปิด + ★ emit
router.put('/:id/status', anyRole, async (req, res) => {
  try {
    const { isOn } = req.body;
    const device = await Device.findByIdAndUpdate(req.params.id, { isOn }, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    emitDeviceUpdate(req, device);
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/wifi
router.put('/:id/wifi', anyRole, async (req, res) => {
  try {
    const { wifiSSID, wifiIP } = req.body;
    const device = await Device.findByIdAndUpdate(req.params.id, { wifiSSID, wifiIP }, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/schedule
router.put('/:id/schedule', anyRole, async (req, res) => {
  try {
    const { schedule } = req.body;
    const device = await Device.findByIdAndUpdate(req.params.id, { schedule }, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/assign-customer
router.put('/:id/assign-customer', managerUp, async (req, res) => {
  try {
    const { customerId, location } = req.body;
    const update = { customerId: customerId || null };
    if (location !== undefined) update.location = location;
    const device = await Device.findByIdAndUpdate(req.params.id, update, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/sensor — ESP32 + ★ emit real-time
router.put('/:id/sensor', async (req, res) => {
  try {
    const { levelMl, status, ip, wifiSSID, firmwareVersion } = req.body;
    const update = { lastSensorUpdate: new Date() };

    if (levelMl !== undefined) {
      update.levelMl = levelMl;
      update.level = Math.round(Math.min(Math.max(levelMl / 10, 0), 100));
    }
    if (status) update.status = status;
    if (ip) update.wifiIP = ip;
    if (wifiSSID) update.wifiSSID = wifiSSID;
    if (firmwareVersion) update.firmwareVersion = firmwareVersion;

    const device = await Device.findByIdAndUpdate(req.params.id, update, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });

    // ★ emit real-time ไปยัง Flutter app ทุกเครื่อง
    emitDeviceUpdate(req, device);

    res.json({ message: 'OK', level: device.level, levelMl: device.levelMl });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// DELETE /api/devices/:id
router.delete('/:id', anyRole, async (req, res) => {
  try {
    const device = await Device.findByIdAndDelete(req.params.id);
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    // ★ emit device removed
    const io = req.app.get('io');
    if (io) io.emit('device:removed', { id: req.params.id });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
