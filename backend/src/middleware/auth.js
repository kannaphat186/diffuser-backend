// src/middleware/auth.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Unchanged from v5.2.1 — no database dependency, only JWT.
// Retained here so server.js + routes can import from the same
// path without repackaging.
// ─────────────────────────────────────────────────────────────
const jwt = require('jsonwebtoken');

const SECRET = process.env.JWT_SECRET;
if (!SECRET || SECRET.length < 16) {
  process.stderr.write(
    '[FATAL] JWT_SECRET is not set or is too short (min 16 chars). ' +
    'Set it in src/.env before starting the backend.\n'
  );
  process.exit(1);
}

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

function adminOnly(req, res, next) {
  verify(req, res, () => {
    if (req.user.role !== 'admin')
      return res.status(403).json({ message: 'เฉพาะ Admin เท่านั้น' });
    next();
  });
}

function managerUp(req, res, next) {
  verify(req, res, () => {
    if (!['admin', 'manager'].includes(req.user.role))
      return res.status(403).json({ message: 'เฉพาะ Admin/Manager เท่านั้น' });
    next();
  });
}

function anyRole(req, res, next) {
  verify(req, res, next);
}

module.exports = { verify, adminOnly, managerUp, anyRole, SECRET };
