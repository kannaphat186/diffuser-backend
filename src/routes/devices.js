const router = require('express').Router();
const { adminOnly, managerUp, anyRole } = require('../middleware/auth');
const { devices, customers, notifications } = require('../database');

router.get('/', anyRole, (req, res) => {
  let result = devices;
  if (req.query.customerId) result = result.filter(d => d.customerId === req.query.customerId);
  if (req.query.search) {
    const s = req.query.search.toLowerCase();
    result = result.filter(d => d.name.toLowerCase().includes(s) || d.serialNumber.toLowerCase().includes(s) || d.location.toLowerCase().includes(s) || d.wifiSSID.toLowerCase().includes(s) || (d.customerId && customers.find(c => c.id === d.customerId)?.name.toLowerCase().includes(s)));
  }
  res.json(result.map(d => ({ ...d, customerName: d.customerId ? customers.find(c => c.id === d.customerId)?.name || '' : '' })));
});

router.get('/:id', anyRole, (req, res) => {
  const d = devices.find(d => d.id === req.params.id);
  if (!d) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  res.json({ ...d, customerName: d.customerId ? customers.find(c => c.id === d.customerId)?.name || '' : '' });
});

router.post('/', managerUp, (req, res) => {
  const { name, serialNumber, ip, mac, customerId, location, groupId, wifiSSID, btAddress } = req.body;
  if (!ip) return res.status(400).json({ message: 'กรอก ip' });
  if (serialNumber && devices.find(d => d.serialNumber === serialNumber)) return res.status(400).json({ message: 'Serial Number ซ้ำ' });
  const device = { id: `d${Date.now()}`, serialNumber: serialNumber || `SS-${Date.now()}`, name: name || '', ip, mac: mac || '', customerId: customerId || null, location: location || '', groupId: groupId || null, status: 'offline', isOn: false, level: 100, battery: 100, pumpOk: true, relayOk: true, wifiSSID: wifiSSID || '', wifiIP: ip, btAddress: btAddress || '', btConnected: false, schedule: [], firmwareVersion: '1.0.0', createdAt: new Date().toISOString() };
  devices.push(device);
  res.status(201).json(device);
});

router.put('/:id', anyRole, (req, res) => {
  const device = devices.find(d => d.id === req.params.id);
  if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  if (req.user.role === 'technician') {
    const { name, location, wifiSSID } = req.body;
    const changes = [];
    if (name !== undefined && name !== device.name) { changes.push(`ชื่อ: "${device.name}" → "${name}"`); device.name = name; }
    if (location !== undefined && location !== device.location) { changes.push(`ตำแหน่ง: "${device.location}" → "${location}"`); device.location = location; }
    if (wifiSSID !== undefined && wifiSSID !== device.wifiSSID) { changes.push(`WiFi: "${device.wifiSSID}" → "${wifiSSID}"`); device.wifiSSID = wifiSSID; }
    if (changes.length > 0) {
      notifications.push({ id: `n${Date.now()}`, type: 'device_edit', title: `ช่าง ${req.user.name} แก้ไขเครื่อง ${device.serialNumber}`, message: changes.join(', '), deviceId: device.id, userId: req.user.id, targetRoles: ['admin', 'manager'], isRead: false, createdAt: new Date().toISOString() });
    }
    const blocked = ['serialNumber', 'ip', 'mac', 'groupId'];
    for (const f of blocked) { if (req.body[f] !== undefined) return res.status(403).json({ message: `Technician ไม่สามารถแก้ไข ${f} ได้` }); }
  } else {
    ['name', 'serialNumber', 'ip', 'mac', 'location', 'groupId', 'wifiSSID', 'wifiIP', 'btAddress'].forEach(f => { if (req.body[f] !== undefined) device[f] = req.body[f]; });
    if (req.body.serialNumber && devices.find(d => d.serialNumber === req.body.serialNumber && d.id !== device.id)) return res.status(400).json({ message: 'Serial Number ซ้ำ' });
  }
  res.json({ ...device, customerName: device.customerId ? customers.find(c => c.id === device.customerId)?.name || '' : '' });
});

router.put('/:id/status', anyRole, (req, res) => {
  const device = devices.find(d => d.id === req.params.id);
  if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  ['isOn', 'level', 'battery', 'status', 'pumpOk', 'relayOk', 'btConnected', 'wifiSSID'].forEach(f => { if (req.body[f] !== undefined) device[f] = req.body[f]; });
  res.json(device);
});

router.put('/:id/schedule', anyRole, (req, res) => {
  const device = devices.find(d => d.id === req.params.id);
  if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  device.schedule = req.body.schedule || [];
  res.json(device);
});

router.put('/:id/wifi', anyRole, (req, res) => {
  const device = devices.find(d => d.id === req.params.id);
  if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  const { ssid, password } = req.body;
  if (!ssid) return res.status(400).json({ message: 'กรอก SSID' });
  device.wifiSSID = ssid;
  if (req.user.role === 'technician') {
    notifications.push({ id: `n${Date.now()}`, type: 'wifi_change', title: `ช่าง ${req.user.name} เปลี่ยน WiFi เครื่อง ${device.serialNumber}`, message: `WiFi ใหม่: ${ssid}`, deviceId: device.id, userId: req.user.id, targetRoles: ['admin', 'manager'], isRead: false, createdAt: new Date().toISOString() });
  }
  res.json({ message: 'เปลี่ยน WiFi สำเร็จ', device });
});

router.put('/:id/assign-customer', managerUp, (req, res) => {
  const device = devices.find(d => d.id === req.params.id);
  if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  const { customerId, location } = req.body;
  if (customerId && !customers.find(c => c.id === customerId)) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
  device.customerId = customerId || null;
  if (location !== undefined) device.location = location;
  res.json(device);
});

router.put('/:id/unassign', managerUp, (req, res) => {
  const device = devices.find(d => d.id === req.params.id);
  if (!device) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  device.customerId = null; device.location = ''; device.schedule = []; device.groupId = null;
  if (req.body.newSerialNumber) { if (devices.find(d => d.serialNumber === req.body.newSerialNumber && d.id !== device.id)) return res.status(400).json({ message: 'Serial Number ซ้ำ' }); device.serialNumber = req.body.newSerialNumber; }
  res.json(device);
});

router.delete('/:id', adminOnly, (req, res) => {
  const idx = devices.findIndex(d => d.id === req.params.id);
  if (idx === -1) return res.status(404).json({ message: 'ไม่พบเครื่อง' });
  devices.splice(idx, 1);
  res.json({ message: 'ลบสำเร็จ' });
});

module.exports = router;
