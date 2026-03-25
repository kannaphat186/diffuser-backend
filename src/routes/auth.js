// routes/auth.js
const router = require('express').Router();
const bcrypt = require('bcryptjs');
const jwt    = require('jsonwebtoken');
const User   = require('../models/User');
const { verify } = require('../middleware/auth');

const SECRET = process.env.JWT_SECRET || 'scent-and-sense-secret-2025';

// Helper: แปลง _id → id
const safeUser = (u) => {
  const obj = u.toObject ? u.toObject() : u;
  const { password, ...rest } = obj;
  return { ...rest, id: rest._id.toString() };
};

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password)
      return res.status(400).json({ message: 'กรอก email และ password' });

    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user)
      return res.status(401).json({ message: 'Email หรือ password ไม่ถูกต้อง' });

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch)
      return res.status(401).json({ message: 'Email หรือ password ไม่ถูกต้อง' });

    user.lastLogin = new Date();
    user.isOnline  = true;
    await user.save({ validateModifiedOnly: true });

    const token = jwt.sign(
      { id: user._id.toString(), email: user.email, role: user.role, name: user.name },
      SECRET,
      { expiresIn: '7d' }
    );

    res.json({ token, user: safeUser(user) });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/auth/logout
router.post('/logout', verify, async (req, res) => {
  try {
    await User.findByIdAndUpdate(req.user.id, { isOnline: false });
    res.json({ message: 'Logout สำเร็จ' });
  } catch (error) {
    res.json({ message: 'OK' }); // fire-and-forget
  }
});

// GET /api/auth/me
router.get('/me', verify, async (req, res) => {
  try {
    const user = await User.findById(req.user.id).select('-password');
    if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
    res.json(safeUser(user));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/auth/forgot-password
router.post('/forgot-password', async (req, res) => {
  // ตอบ success เสมอ ป้องกัน email enumeration
  res.json({ message: 'ถ้า email นี้มีในระบบ จะได้รับ email รีเซ็ตรหัสผ่าน' });
});

// POST /api/auth/reset-password
router.post('/reset-password', async (req, res) => {
  try {
    const { userId, newPassword } = req.body;
    if (!userId || !newPassword)
      return res.status(400).json({ message: 'กรอก userId และ newPassword' });

    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });

    user.password = newPassword; // pre-save hook จะ hash ให้
    await user.save();
    res.json({ message: 'เปลี่ยนรหัสผ่านสำเร็จ' });
  } catch (error) {
    console.error('Reset password error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
