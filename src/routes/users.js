// routes/users.js
const router = require('express').Router();
const { adminOnly, managerUp } = require('../middleware/auth');
const User = require('../models/User');

const fmt = (u) => {
  const obj = u.toObject ? u.toObject() : u;
  const { password, ...rest } = obj;
  return { ...rest, id: rest._id.toString() };
};

// GET /api/users
router.get('/', managerUp, async (req, res) => {
  try {
    const users = await User.find().select('-password').sort({ createdAt: -1 });
    res.json(users.map(fmt));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// GET /api/users/online
router.get('/online', managerUp, async (req, res) => {
  try {
    const users = await User.find({ isOnline: true }).select('-password');
    res.json(users.map(fmt));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/users
router.post('/', adminOnly, async (req, res) => {
  try {
    const { name, email, password, role = 'technician' } = req.body;
    if (!name || !email || !password)
      return res.status(400).json({ message: 'กรอกข้อมูลให้ครบ' });
    if (!['admin', 'manager', 'technician'].includes(role))
      return res.status(400).json({ message: 'Role ไม่ถูกต้อง (admin, manager, technician)' });

    const existing = await User.findOne({ email: email.toLowerCase() });
    if (existing) return res.status(400).json({ message: 'อีเมลนี้มีในระบบแล้ว' });

    const user = new User({ name, email, password, role });
    await user.save();
    res.status(201).json(fmt(user));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/users/:id
router.put('/:id', adminOnly, async (req, res) => {
  try {
    const user = await User.findById(req.params.id);
    if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });

    const { name, email, password, role } = req.body;
    if (name)  user.name  = name;
    if (email) user.email = email.toLowerCase();
    if (role && ['admin', 'manager', 'technician'].includes(role)) user.role = role;
    if (password) user.password = password; // pre-save hook จะ hash ให้

    await user.save();
    res.json(fmt(user));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// DELETE /api/users/:id
router.delete('/:id', adminOnly, async (req, res) => {
  try {
    if (req.params.id === req.user.id)
      return res.status(400).json({ message: 'ลบตัวเองไม่ได้' });

    const user = await User.findByIdAndDelete(req.params.id);
    if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
