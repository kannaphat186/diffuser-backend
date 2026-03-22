const router = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const { serviceLogs, devices, users, customers } = require('../database');

router.get('/', anyRole, (req, res) => {
  let result = serviceLogs;
  if (req.user.role === 'technician') result = result.filter(l => l.technicianId === req.user.id);
  if (req.query.deviceId) result = result.filter(l => l.deviceId === req.query.deviceId);
  if (req.query.customerId) {
    const ids = devices.filter(d => d.customerId === req.query.customerId).map(d => d.id);
    result = result.filter(l => ids.includes(l.deviceId));
  }
  const enriched = result.map(l => {
    const d = devices.find(d => d.id === l.deviceId);
    const t = users.find(u => u.id === l.technicianId);
    const c = d?.customerId ? customers.find(c => c.id === d.customerId) : null;
    return { ...l, deviceName: d?.name || '', deviceSerial: d?.serialNumber || '', customerName: c?.name || '', technicianName: t?.name || '' };
  });
  enriched.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json(enriched);
});

router.post('/', anyRole, (req, res) => {
  const { deviceId, type, description, notes, photos } = req.body;
  if (!deviceId || !type) return res.status(400).json({ message: 'กรอก deviceId และ type' });
  if (!devices.find(d => d.id === deviceId)) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  const validTypes = ['refill', 'repair', 'inspection', 'installation', 'uninstall', 'other'];
  if (!validTypes.includes(type)) return res.status(400).json({ message: `type ต้องเป็น: ${validTypes.join(', ')}` });

  const log = { id: Date.now().toString(), deviceId, technicianId: req.user.id, type, description: description || '', notes: notes || '', photos: photos || [], createdAt: new Date().toISOString() };
  serviceLogs.push(log);

  const d = devices.find(d => d.id === deviceId);
  const c = d?.customerId ? customers.find(c => c.id === d.customerId) : null;
  res.status(201).json({ ...log, deviceName: d?.name || '', deviceSerial: d?.serialNumber || '', customerName: c?.name || '', technicianName: req.user.name });
});

router.get('/export', managerUp, (req, res) => {
  let result = serviceLogs;
  const { customerId, startDate, endDate } = req.query;
  if (customerId) { const ids = devices.filter(d => d.customerId === customerId).map(d => d.id); result = result.filter(l => ids.includes(l.deviceId)); }
  if (startDate) result = result.filter(l => new Date(l.createdAt) >= new Date(startDate));
  if (endDate) result = result.filter(l => new Date(l.createdAt) <= new Date(endDate));

  const enriched = result.map(l => {
    const d = devices.find(d => d.id === l.deviceId);
    const t = users.find(u => u.id === l.technicianId);
    const c = d?.customerId ? customers.find(c => c.id === d.customerId) : null;
    return { date: l.createdAt, type: l.type, description: l.description, notes: l.notes, deviceName: d?.name || '', deviceSerial: d?.serialNumber || '', customerName: c?.name || '', technicianName: t?.name || '', photoCount: l.photos?.length || 0 };
  });
  enriched.sort((a, b) => new Date(b.date) - new Date(a.date));
  const ci = customerId ? customers.find(c => c.id === customerId) : null;
  res.json({ reportTitle: ci ? `รายงานเซอร์วิส - ${ci.name}` : 'รายงานเซอร์วิสทั้งหมด', generatedAt: new Date().toISOString(), totalRecords: enriched.length, records: enriched });
});

module.exports = router;
