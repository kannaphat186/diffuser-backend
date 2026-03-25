// seed.js — ใส่ข้อมูลเริ่มต้นเข้า MongoDB
require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt   = require('bcryptjs');
const connectDB = require('./config/db');

const User       = require('./models/User');
const Customer   = require('./models/Customer');
const Device     = require('./models/Device');
const ServiceLog = require('./models/ServiceLog');
const Notification = require('./models/Notification');

async function seed() {
  await connectDB();

  // ลบข้อมูลเก่าทั้งหมด
  await Promise.all([
    User.deleteMany({}),
    Customer.deleteMany({}),
    Device.deleteMany({}),
    ServiceLog.deleteMany({}),
    Notification.deleteMany({}),
  ]);
  console.log('🗑️  Cleared old data');

  // --- Users ---
  const hash = await bcrypt.hash('password', 10);
  const [admin, manager, tech] = await User.insertMany([
    { name: 'Admin User',   email: 'admin@scentandsense.com',   password: hash, role: 'admin' },
    { name: 'Manager User', email: 'manager@scentandsense.com', password: hash, role: 'manager' },
    { name: 'Tech User',    email: 'tech@scentandsense.com',    password: hash, role: 'technician' },
  ]);
  console.log('✅ Users created (password = "password")');

  // --- Customers ---
  const [c1, c2, c3] = await Customer.insertMany([
    { name: 'Grand Palace Hotel', contactName: 'คุณสมชาย', contactPhone: '081-234-5678', contactEmail: 'somchai@grandpalace.com', address: '123 ถ.สุขุมวิท กรุงเทพฯ', packageQty: 10 },
    { name: 'Spa Zenith',         contactName: 'คุณวิภา',   contactPhone: '089-876-5432', contactEmail: 'vipa@spazenith.com',      address: '456 ถ.พหลโยธิน กรุงเทพฯ', packageQty: 5 },
    { name: 'Rose Cafe',          contactName: 'คุณรัตนา', contactPhone: '092-111-2222', contactEmail: 'ratana@rosecafe.com',     address: '789 ถ.ลาดพร้าว กรุงเทพฯ', packageQty: 3 },
  ]);
  console.log('✅ Customers created');

  // --- Devices ---
  const [d1, d2, d3, d4] = await Device.insertMany([
    {
      serialNumber: 'SS-2025-001', name: 'Diffuser ล็อบบี้',
      customerId: c1._id, location: 'ล็อบบี้ชั้น 1',
      status: 'online', isOn: true, level: 75,
      wifiSSID: 'GrandPalace_5G', wifiIP: '192.168.1.101',
      mac: 'AA:BB:CC:DD:EE:01',
      schedule: [{ startTime: '08:00', endTime: '18:00', workSeconds: 30, pauseSeconds: 60, days: [true,true,true,true,true,false,false] }],
    },
    {
      serialNumber: 'SS-2025-002', name: 'Diffuser ห้องประชุม',
      customerId: c1._id, location: 'ห้องประชุมชั้น 2',
      status: 'online', isOn: false, level: 30,
      wifiSSID: 'GrandPalace_5G', wifiIP: '192.168.1.102',
      mac: 'AA:BB:CC:DD:EE:02', schedule: [],
    },
    {
      serialNumber: 'SS-2025-003', name: 'Diffuser สปา Zone A',
      customerId: c2._id, location: 'สปา Zone A',
      status: 'online', isOn: true, level: 90,
      wifiSSID: 'SpaZenith_WiFi', wifiIP: '192.168.2.101',
      mac: 'AA:BB:CC:DD:EE:03',
      schedule: [{ startTime: '09:00', endTime: '21:00', workSeconds: 45, pauseSeconds: 90, days: [true,true,true,true,true,true,true] }],
    },
    {
      serialNumber: 'SS-2025-004', name: '',
      customerId: c1._id, location: '',
      status: 'offline', isOn: false, level: 0,
      mac: 'AA:BB:CC:DD:EE:04', schedule: [],
    },
  ]);
  console.log('✅ Devices created');

  // --- Service Logs ---
  await ServiceLog.insertMany([
    { deviceId: d1._id, technicianId: tech._id, type: 'refill',       description: 'เติมน้ำหอม 15% -> 100%',           notes: 'น้ำหอมกลิ่นลาเวนเดอร์' },
    { deviceId: d2._id, technicianId: tech._id, type: 'repair',       description: 'เปลี่ยนปั๊ม',                       notes: 'ปั๊มเก่าเสีย เปลี่ยนตัวใหม่' },
    { deviceId: d3._id, technicianId: tech._id, type: 'installation', description: 'ติดตั้งเครื่องใหม่ สปา Zone A',    notes: '' },
    { deviceId: d1._id, technicianId: tech._id, type: 'inspection',   description: 'ตรวจเช็คประจำเดือน',                notes: 'ทุกอย่างปกติ' },
  ]);
  console.log('✅ Service logs created');

  console.log('\n🎉 Seed สำเร็จ! พร้อมใช้งาน');
  console.log('─────────────────────────────────');
  console.log('📧 admin@scentandsense.com   / password');
  console.log('📧 manager@scentandsense.com / password');
  console.log('📧 tech@scentandsense.com    / password');
  console.log('─────────────────────────────────');

  await mongoose.disconnect();
  process.exit(0);
}

seed().catch(err => {
  console.error('❌ Seed error:', err);
  process.exit(1);
});
