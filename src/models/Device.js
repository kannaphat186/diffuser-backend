// models/Device.js — v3.0 เพิ่ม levelMl สำหรับ ESP32 sensor
const mongoose = require('mongoose');

const scheduleSchema = new mongoose.Schema({
  startTime:    String,
  endTime:      String,
  workSeconds:  Number,
  pauseSeconds: Number,
  days:         [Boolean],
}, { _id: false });

const deviceSchema = new mongoose.Schema({
  serialNumber:    { type: String, required: true, unique: true },
  name:            { type: String, default: '' },
  ip:              { type: String, default: '' },
  mac:             { type: String, default: '' },
  customerId:      { type: mongoose.Schema.Types.ObjectId, ref: 'Customer', default: null },
  location:        { type: String, default: '' },
  groupId:         { type: String, default: null },
  status:          { type: String, enum: ['online', 'offline', 'error'], default: 'offline' },
  isOn:            { type: Boolean, default: false },
  level:           { type: Number, default: 100 },
  // ★ NEW: ค่า mL จริงจาก VL53L0X sensor (null = ยังไม่มี sensor)
  levelMl:         { type: Number, default: null },
  battery:         { type: Number, default: 100 },
  pumpOk:          { type: Boolean, default: true },
  relayOk:         { type: Boolean, default: true },
  wifiSSID:        { type: String, default: '' },
  wifiIP:          { type: String, default: '' },
  btAddress:       { type: String, default: '' },
  btConnected:     { type: Boolean, default: false },
  schedule:        [scheduleSchema],
  firmwareVersion: { type: String, default: '1.0.0' },
  // ★ NEW: timestamp ล่าสุดที่ sensor ส่งข้อมูล
  lastSensorUpdate: { type: Date, default: null },
}, { timestamps: true });

module.exports = mongoose.model('Device', deviceSchema);
