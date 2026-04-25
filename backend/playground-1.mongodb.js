// 1. บังคับให้ใช้ฐานข้อมูลชื่อ diffuser_db
use('diffuser_db'); 

// 2. กำหนดค่า ID และ Serial ของเครื่องคุณ
const canonicalId = ObjectId("69d3f8f6176599d3bf4e36a8"); 
const canonicalSerial = "SS-2026-001";

// 3. รันคำสั่งค้นหา
db.devices.find(
  {
    $or: [
      { _id: canonicalId },
      { serialNumber: canonicalSerial }
    ]
  },
  {
    _id: 1,
    serialNumber: 1,
    status: 1,
    wifiSSID: 1,
    firmwareVersion: 1,
    updatedAt: 1
  }
).pretty();