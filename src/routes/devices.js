// routes/devices.js — ★ มี POST /api/devices แล้ว!
const router   = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const Device   = require('../models/Device');
const Customer = require('../models/Customer');

// Helper: format response ให้ id เป็น string และเพิ่ม customerName
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
  };
};

// GET /api/devices
router.get('/', anyRole, async (req, res) => {
  try {
    const [devices, customers] = await Promise.all([
      Device.find().sort({ createdAt: -1 }),
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

// ★ POST /api/devices — สร้างเครื่องใหม่
router.post('/', managerUp, async (req, res) => {
  try {
    const { serialNumber, name, location, customerId, level, wifiSSID } = req.body;
    if (!serialNumber)
      return res.status(400).json({ message: 'กรอก serialNumber' });

    const existing = await Device.findOne({ serialNumber });
    if (existing)
      return res.status(400).json({ message: 'Serial number นี้มีในระบบแล้ว' });

    const device = new Device({
      serialNumber,
      name:       name       || '',
      location:   location   || '',
      customerId: customerId || null,
      level:      level      ?? 100,
      wifiSSID:   wifiSSID   || '',
    });
    await device.save();
    res.status(201).json(await fmt(device));
  } catch (error) {
    console.error('Create device error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id — แก้ไขข้อมูลเครื่อง
router.put('/:id', managerUp, async (req, res) => {
  try {
    const device = await Device.findByIdAndUpdate(req.params.id, req.body, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/status — เปิด/ปิด
router.put('/:id/status', anyRole, async (req, res) => {
  try {
    const { isOn } = req.body;
    const device = await Device.findByIdAndUpdate(req.params.id, { isOn }, { new: true });
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/devices/:id/wifi — เปลี่ยน WiFi
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

// PUT /api/devices/:id/schedule — ตั้งตาราง
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

// PUT /api/devices/:id/assign-customer — ผูกลูกค้า
router.put('/:id/assign-customer', managerUp, async (req, res) => {
  try {
    const { customerId } = req.body;
    const device = await Device.findByIdAndUpdate(
      req.params.id,
      { customerId: customerId || null },
      { new: true }
    );
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json(await fmt(device));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// DELETE /api/devices/:id
router.delete('/:id', managerUp, async (req, res) => {
  try {
    const device = await Device.findByIdAndDelete(req.params.id);
    if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
