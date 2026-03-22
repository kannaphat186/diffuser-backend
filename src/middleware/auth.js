// middleware/auth.js
const jwt = require('jsonwebtoken');

const SECRET = process.env.JWT_SECRET || 'scent-and-sense-secret-2025';

// ตรวจ JWT Token
function verify(req, res, next) {
  const token = req.header('Authorization')?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ message: 'ไม่มี token การยืนยันตัวตน' });
  try {
    req.user = jwt.verify(token, SECRET);
    next();
  } catch (err) {
    res.status(401).json({ message: 'Token ไม่ถูกต้องหรือหมดอายุ' });
  }
}

// เฉพาะ Admin เท่านั้น
function adminOnly(req, res, next) {
  verify(req, res, () => {
    if (req.user.role !== 'admin') return res.status(403).json({ message: 'ต้องเป็น Admin เท่านั้น' });
    next();
  });
}

// Admin หรือ Manager
function managerUp(req, res, next) {
  verify(req, res, () => {
    if (!['admin', 'manager'].includes(req.user.role)) return res.status(403).json({ message: 'ต้องเป็น Admin หรือ Manager' });
    next();
  });
}

// ทุก Role (แค่ต้อง login)
function anyRole(req, res, next) {
  verify(req, res, next);
}

module.exports = { verify, adminOnly, managerUp, anyRole, SECRET };
