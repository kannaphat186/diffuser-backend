const router = require('express').Router();
const { adminOnly, managerUp, anyRole } = require('../middleware/auth');
const { customers, devices } = require('../database');

router.get('/', anyRole, (req, res) => {
  const result = customers.map(c => ({
    ...c,
    deviceCount: devices.filter(d => d.customerId === c.id).length,
    onlineCount: devices.filter(d => d.customerId === c.id && d.status === 'online').length,
    alertCount: devices.filter(d => d.customerId === c.id && (d.level < 20 || d.status === 'offline')).length,
  }));
  res.json(result);
});

router.get('/:id', anyRole, (req, res) => {
  const c = customers.find(c => c.id === req.params.id);
  if (!c) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
  const devs = devices.filter(d => d.customerId === c.id);
  res.json({ ...c, deviceCount: devs.length, onlineCount: devs.filter(d => d.status === 'online').length, alertCount: devs.filter(d => d.level < 20 || d.status === 'offline').length, devices: devs });
});

router.post('/', managerUp, (req, res) => {
  const { name, contactName, contactPhone, contactEmail, address, packageQty, notes } = req.body;
  if (!name) return res.status(400).json({ message: 'กรอกชื่อลูกค้า' });
  const customer = { id: `c${Date.now()}`, name, contactName: contactName || '', contactPhone: contactPhone || '', contactEmail: contactEmail || '', address: address || '', packageQty: packageQty || 0, notes: notes || '', createdAt: new Date().toISOString() };
  customers.push(customer);
  res.status(201).json({ ...customer, deviceCount: 0, onlineCount: 0, alertCount: 0 });
});

router.put('/:id', managerUp, (req, res) => {
  const c = customers.find(c => c.id === req.params.id);
  if (!c) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
  ['name', 'contactName', 'contactPhone', 'contactEmail', 'address', 'packageQty', 'notes'].forEach(f => { if (req.body[f] !== undefined) c[f] = req.body[f]; });
  res.json(c);
});

router.delete('/:id', adminOnly, (req, res) => {
  const idx = customers.findIndex(c => c.id === req.params.id);
  if (idx === -1) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
  devices.filter(d => d.customerId === req.params.id).forEach(d => { d.customerId = null; d.location = ''; });
  customers.splice(idx, 1);
  res.json({ message: 'ลบสำเร็จ' });
});

module.exports = router;
