// src/routes/users.js — v6.0.0
const router = require('express').Router();
const { adminOnly, managerUp } = require('../middleware/auth');
const users = require('../repositories/users');

const normalizeEmail = (value = '') => String(value).trim().toLowerCase();

router.get('/', managerUp, async (req, res) => {
  try {
    res.json(await users.listAll());
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.get('/online', managerUp, async (req, res) => {
  try {
    res.json(await users.listOnline());
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// Admin only — creating accounts is privileged.
router.post('/', adminOnly, async (req, res) => {
  try {
    const { name, email, password, role = 'technician' } = req.body;
    const normalizedEmail = normalizeEmail(email);
    if (!name || !normalizedEmail || !password) {
      return res.status(400).json({ message: 'กรอกข้อมูลให้ครบ' });
    }
    if (String(password).length < 6) {
      return res.status(400).json({ message: 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร' });
    }
    if (!['admin', 'manager', 'technician'].includes(role)) {
      return res.status(400).json({ message: 'Role ไม่ถูกต้อง (admin, manager, technician)' });
    }

    if (await users.existsByEmail(normalizedEmail)) {
      return res.status(400).json({ message: 'อีเมลนี้มีในระบบแล้ว' });
    }

    const user = await users.create({
      name: String(name).trim(),
      email: normalizedEmail,
      password,
      role,
    });
    res.status(201).json(user);
  } catch (error) {
    process.stderr.write(`[users] create error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// Manager / admin edit — managers cannot edit other admins/managers
// and cannot change roles.
router.put('/:id', managerUp, async (req, res) => {
  try {
    const target = await users.findById(req.params.id);
    if (!target) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });

    const actorRole = req.user.role;
    const actorId = req.user.id;
    const isSelf = target.id === actorId;

    if (actorRole === 'manager') {
      if (!isSelf && (target.role === 'admin' || target.role === 'manager')) {
        return res.status(403).json({
          message: 'Manager ไม่มีสิทธิ์แก้ไขบัญชี Admin/Manager อื่น',
        });
      }
    }

    const patch = {};
    const { name, email, password, role } = req.body;
    if (name !== undefined) patch.name = String(name).trim();

    if (email !== undefined) {
      const normalizedEmail = normalizeEmail(email);
      if (await users.existsByEmail(normalizedEmail, target.id)) {
        return res.status(400).json({ message: 'อีเมลนี้มีในระบบแล้ว' });
      }
      patch.email = normalizedEmail;
    }

    // Only admins can change roles.
    if (role !== undefined && ['admin', 'manager', 'technician'].includes(role) && actorRole === 'admin') {
      patch.role = role;
    }

    if (password !== undefined) {
      if (String(password).length < 6) {
        return res.status(400).json({ message: 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร' });
      }
      patch.password = String(password);
    }

    const updated = await users.updateById(target.id, patch);
    res.json(updated);
  } catch (error) {
    process.stderr.write(`[users] update error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.delete('/:id', adminOnly, async (req, res) => {
  try {
    if (req.params.id === req.user.id) {
      return res.status(400).json({ message: 'ลบตัวเองไม่ได้' });
    }
    const ok = await users.deleteById(req.params.id);
    if (!ok) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
