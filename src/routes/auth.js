const router = require('express').Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { users } = require('../database');
const { SECRET, verify } = require('../middleware/auth');

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ message: 'กรุณากรอกอีเมลและรหัสผ่าน' });

    const user = users.find(u => u.email === email.toLowerCase());
    if (!user) return res.status(401).json({ message: 'อีเมลหรือรหัสผ่านไม่ถูกต้อง' });

    const isValid = await bcrypt.compare(password, user.password);
    if (!isValid) return res.status(401).json({ message: 'อีเมลหรือรหัสผ่านไม่ถูกต้อง' });

    user.lastLogin = new Date().toISOString();
    user.isOnline = true;

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role, name: user.name },
      SECRET,
      { expiresIn: '30d' }
    );

    const { password: _, ...safe } = user;
    res.json({ token, user: safe });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/auth/logout
router.post('/logout', verify, (req, res) => {
  const user = users.find(u => u.id === req.user.id);
  if (user) user.isOnline = false;
  res.json({ message: 'ออกจากระบบแล้ว' });
});

// GET /api/auth/me
router.get('/me', verify, (req, res) => {
  const user = users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
  const { password: _, ...safe } = user;
  res.json(safe);
});

// POST /api/auth/forgot-password — ขอรีเซ็ตรหัสผ่าน
router.post('/forgot-password', (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ message: 'กรอกอีเมล' });

  const user = users.find(u => u.email === email.toLowerCase());
  // ไม่บอกว่าเจอหรือไม่เจอ (security)
  if (user) {
    // สร้าง reset token อายุ 1 ชั่วโมง
    const resetToken = jwt.sign({ id: user.id, type: 'reset' }, SECRET, { expiresIn: '1h' });
    user.resetToken = resetToken;
    user.resetExpiry = new Date(Date.now() + 3600000).toISOString();
    console.log(`🔑 Reset token for ${email}: ${resetToken}`);
    console.log(`📧 Admin: ส่ง token นี้ให้ ${user.name} (${user.email})`);
  }

  res.json({ message: 'หากอีเมลนี้มีในระบบ Admin จะติดต่อกลับ' });
});

// POST /api/auth/reset-password — Admin รีเซ็ตให้ได้เลย
router.post('/reset-password', verify, async (req, res) => {
  try {
    // Admin รีเซ็ตรหัสผ่านให้ user คนอื่น
    if (req.user.role === 'admin') {
      const { userId, newPassword } = req.body;
      if (!userId || !newPassword) return res.status(400).json({ message: 'กรอก userId และ newPassword' });
      const target = users.find(u => u.id === userId);
      if (!target) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
      target.password = await bcrypt.hash(newPassword, 10);
      return res.json({ message: `รีเซ็ตรหัสผ่านของ ${target.name} สำเร็จ` });
    }
    // User เปลี่ยนรหัสตัวเอง
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) return res.status(400).json({ message: 'กรอกรหัสผ่านปัจจุบันและใหม่' });
    const user = users.find(u => u.id === req.user.id);
    if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
    const valid = await bcrypt.compare(currentPassword, user.password);
    if (!valid) return res.status(401).json({ message: 'รหัสผ่านปัจจุบันไม่ถูกต้อง' });
    user.password = await bcrypt.hash(newPassword, 10);
    res.json({ message: 'เปลี่ยนรหัสผ่านสำเร็จ' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
