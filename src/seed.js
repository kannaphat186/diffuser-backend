// seed.js — Production (ไม่มีข้อมูลปลอม)
require('dotenv').config();
const mongoose   = require('mongoose');
const bcrypt     = require('bcryptjs');
const connectDB  = require('./config/db');
const User       = require('./models/User');
const Customer   = require('./models/Customer');
const Device     = require('./models/Device');
const ServiceLog = require('./models/ServiceLog');
const Notification = require('./models/Notification');

async function seed() {
  await connectDB();
  console.log('⚠️  ลบข้อมูลทั้งหมดใน 3 วินาที... (Ctrl+C เพื่อยกเลิก)');
  await new Promise(r => setTimeout(r, 3000));

  await Promise.all([
    User.deleteMany({}), Customer.deleteMany({}),
    Device.deleteMany({}), ServiceLog.deleteMany({}),
    Notification.deleteMany({}),
  ]);

  const hash = await bcrypt.hash('password', 10);
  await User.create({ name: 'Admin', email: 'admin@scentandsense.com', password: hash, role: 'admin' });

  console.log('\n✅ พร้อมใช้งาน');
  console.log('📧 admin@scentandsense.com / password');
  console.log('เข้าแอปแล้วเพิ่มลูกค้า/เครื่อง/ผู้ใช้จริงได้เลย\n');
  await mongoose.disconnect();
  process.exit(0);
}
seed().catch(e => { console.error('❌', e); process.exit(1); });
