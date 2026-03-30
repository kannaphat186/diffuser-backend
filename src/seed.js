// seed.js — Production (ไม่มีข้อมูลปลอม)
require('dotenv').config();
const mongoose     = require('mongoose');
const connectDB    = require('./config/db');
const User         = require('./models/User');
const Customer     = require('./models/Customer');
const Device       = require('./models/Device');
const ServiceLog   = require('./models/ServiceLog');
const Notification = require('./models/Notification');

async function seed() {
  await connectDB();
  console.log('⚠️  ลบข้อมูลทั้งหมดใน 3 วินาที... (Ctrl+C เพื่อยกเลิก)');
  await new Promise(r => setTimeout(r, 3000));

  await Promise.all([
    User.deleteMany({}),
    Customer.deleteMany({}),
    Device.deleteMany({}),
    ServiceLog.deleteMany({}),
    Notification.deleteMany({}),
  ]);

  // ส่ง plain password — ให้ User model pre('save') hook hash ให้อัตโนมัติ
  await User.create({
    name: 'Admin',
    email: 'admin@scentandsense.com',
    password: 'password',
    role: 'admin',
  });

  console.log('\n✅ พร้อมใช้งาน');
  console.log('👤 admin@scentandsense.com / password');
  console.log('เข้าแอปแล้วเพิ่มลูกค้า/เครื่อง/ผู้ใช้จริง ได้เลย\n');
  await mongoose.disconnect();
  process.exit(0);
}

seed().catch(e => { console.error('❌', e); process.exit(1); });
