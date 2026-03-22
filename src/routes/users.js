// routes/users.js
const router = require('express').Router();
const bcrypt = require('bcryptjs');
const { adminOnly, managerUp } = require('../middleware/auth');
const { users } = require('../database');

// GET /api/users — ดูรายชื่อผู้ใช้ทั้งหมด (admin + manager)
router.get('/', managerUp, (req, res) => {
  const safeUsers = users.map(({ password: _, ...u }) => u);
  res.json(safeUsers);
});

// GET /api/users/online — ดูว่าใครออนไลน์อยู่ (admin + manager)
router.get('/online', managerUp, (req, res) => {
  const onlineUsers = users
    .filter(u => u.isOnline)
    .map(({ password: _, ...u }) => u);
  res.json(onlineUsers);
});

// POST /api/users — สร้างผู้ใช้ใหม่ (admin only)
router.post('/', adminOnly, async (req, res) => {
  try {
    const { name, email, password, role = 'technician' } = req.body;
    if (!name || !email || !password) return res.status(400).json({ message: 'กรอกข้อมูลให้ครบ' });
    if (!['admin', 'manager', 'technician'].includes(role)) return res.status(400).json({ message: 'Role ไม่ถูกต้อง (admin, manager, technician)' });
    if (users.find(u => u.email === email.toLowerCase())) return res.status(400).json({ message: 'อีเมลนี้มีในระบบแล้ว' });

    const newUser = {
      id: Date.now().toString(),
      name,
      email: email.toLowerCase(),
      password: await bcrypt.hash(password, 10),
      role,
      lastLogin: null,
      isOnline: false,
      createdAt: new Date().toISOString(),
    };
    users.push(newUser);
    const { password: _, ...safe } = newUser;
    res.status(201).json(safe);
  } catch (error) {
    console.error('Create user error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/users/:id — แก้ไขผู้ใช้ (admin only)
router.put('/:id', adminOnly, async (req, res) => {
  try {
    const idx = users.findIndex(u => u.id === req.params.id);
    if (idx === -1) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });

    const { name, email, password, role } = req.body;
    if (name) users[idx].name = name;
    if (email) users[idx].email = email.toLowerCase();
    if (role && ['admin', 'manager', 'technician'].includes(role)) users[idx].role = role;
    if (password) users[idx].password = await bcrypt.hash(password, 10);

    const { password: _, ...safe } = users[idx];
    res.json(safe);
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// DELETE /api/users/:id — ลบผู้ใช้ (admin only)
router.delete('/:id', adminOnly, (req, res) => {
  const idx = users.findIndex(u => u.id === req.params.id);
  if (idx === -1) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
  if (users[idx].id === req.user.id) return res.status(400).json({ message: 'ลบตัวเองไม่ได้' });
  users.splice(idx, 1);
  res.json({ message: 'ลบสำเร็จ' });
});

module.exports = router;
