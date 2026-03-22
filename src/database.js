// database.js — In-memory database v4
// 3 Role: admin, manager, technician
// + ลูกค้า (customers) + Log เซอร์วิส + แพ็คเกจเครื่อง

const bcrypt = require('bcryptjs');
const hash = bcrypt.hashSync('password', 10);

const users = [
  { id: '1', name: 'Admin User', email: 'admin@scentandsense.com', password: hash, role: 'admin', lastLogin: null, isOnline: false, createdAt: new Date().toISOString() },
  { id: '2', name: 'Manager User', email: 'manager@scentandsense.com', password: hash, role: 'manager', lastLogin: null, isOnline: false, createdAt: new Date().toISOString() },
  { id: '3', name: 'Tech User', email: 'tech@scentandsense.com', password: hash, role: 'technician', lastLogin: null, isOnline: false, createdAt: new Date().toISOString() },
];

const customers = [
  { id: 'c1', name: 'Grand Palace Hotel', contactName: 'คุณสมชาย', contactPhone: '081-234-5678', contactEmail: 'somchai@grandpalace.com', address: '123 ถ.สุขุมวิท กรุงเทพฯ', packageQty: 10, notes: '', createdAt: new Date().toISOString() },
  { id: 'c2', name: 'Spa Zenith', contactName: 'คุณวิภา', contactPhone: '089-876-5432', contactEmail: 'vipa@spazenith.com', address: '456 ถ.พหลโยธิน กรุงเทพฯ', packageQty: 5, notes: '', createdAt: new Date().toISOString() },
  { id: 'c3', name: 'Rose Cafe', contactName: 'คุณรัตนา', contactPhone: '092-111-2222', contactEmail: 'ratana@rosecafe.com', address: '789 ถ.ลาดพร้าว กรุงเทพฯ', packageQty: 3, notes: '', createdAt: new Date().toISOString() },
];

const devices = [
  { id: 'd1', serialNumber: 'SS-2025-001', name: 'Diffuser ล็อบบี้', ip: '192.168.1.101', mac: 'AA:BB:CC:DD:EE:01', customerId: 'c1', location: 'ล็อบบี้ชั้น 1', groupId: null, status: 'online', isOn: true, level: 75, battery: 100, pumpOk: true, relayOk: true, wifiSSID: 'GrandPalace_5G', wifiIP: '192.168.1.101', btAddress: 'AA:BB:CC:DD:EE:01', btConnected: false, schedule: [{ startTime: '08:00', endTime: '18:00', workSeconds: 30, pauseSeconds: 60, days: [true,true,true,true,true,false,false] }], firmwareVersion: '1.0.0', createdAt: new Date().toISOString() },
  { id: 'd2', serialNumber: 'SS-2025-002', name: 'Diffuser ห้องประชุม', ip: '192.168.1.102', mac: 'AA:BB:CC:DD:EE:02', customerId: 'c1', location: 'ห้องประชุมชั้น 2', groupId: null, status: 'online', isOn: false, level: 30, battery: 100, pumpOk: true, relayOk: true, wifiSSID: 'GrandPalace_5G', wifiIP: '192.168.1.102', btAddress: 'AA:BB:CC:DD:EE:02', btConnected: false, schedule: [], firmwareVersion: '1.0.0', createdAt: new Date().toISOString() },
  { id: 'd3', serialNumber: 'SS-2025-003', name: 'Diffuser สปา Zone A', ip: '192.168.2.101', mac: 'AA:BB:CC:DD:EE:03', customerId: 'c2', location: 'สปา Zone A', groupId: null, status: 'online', isOn: true, level: 90, battery: 100, pumpOk: true, relayOk: true, wifiSSID: 'SpaZenith_WiFi', wifiIP: '192.168.2.101', btAddress: 'AA:BB:CC:DD:EE:03', btConnected: false, schedule: [{ startTime: '09:00', endTime: '21:00', workSeconds: 45, pauseSeconds: 90, days: [true,true,true,true,true,true,true] }], firmwareVersion: '1.0.0', createdAt: new Date().toISOString() },
  { id: 'd4', serialNumber: 'SS-2025-004', name: '', ip: '192.168.1.103', mac: 'AA:BB:CC:DD:EE:04', customerId: 'c1', location: '', groupId: null, status: 'offline', isOn: false, level: 0, battery: 50, pumpOk: true, relayOk: true, wifiSSID: '', wifiIP: '', btAddress: 'AA:BB:CC:DD:EE:04', btConnected: false, schedule: [], firmwareVersion: '1.0.0', createdAt: new Date().toISOString() },
];

const serviceLogs = [
  { id: 'sl1', deviceId: 'd1', technicianId: '3', type: 'refill', description: 'เติมน้ำหอม 15% -> 100%', notes: 'น้ำหอมกลิ่นลาเวนเดอร์', photos: [], createdAt: '2026-03-18T10:30:00.000Z' },
  { id: 'sl2', deviceId: 'd2', technicianId: '3', type: 'repair', description: 'เปลี่ยนปั๊ม', notes: 'ปั๊มเก่าเสีย เปลี่ยนตัวใหม่', photos: [], createdAt: '2026-03-17T14:00:00.000Z' },
  { id: 'sl3', deviceId: 'd3', technicianId: '3', type: 'installation', description: 'ติดตั้งเครื่องใหม่ สปา Zone A', notes: '', photos: [], createdAt: '2026-03-10T11:00:00.000Z' },
  { id: 'sl4', deviceId: 'd1', technicianId: '3', type: 'inspection', description: 'ตรวจเช็คประจำเดือน', notes: 'ทุกอย่างปกติ', photos: [], createdAt: '2026-03-16T09:00:00.000Z' },
];

const notifications = [];

module.exports = { users, customers, devices, serviceLogs, notifications };
