// src/routes/auth.js — v6.0.0
const router = require('express').Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const users = require('../repositories/users');
const fcmTokens = require('../repositories/fcm_tokens');
const { verify, SECRET } = require('../middleware/auth');

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ message: 'กรอก email และ password' });
    }

    const normalized = String(email).trim().toLowerCase();
    const user = await users.findByEmail(normalized);
    if (!user) {
      return res.status(401).json({ message: 'Email หรือ password ไม่ถูกต้อง' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Email หรือ password ไม่ถูกต้อง' });
    }

    await users.setLoginState(user.id, {
      isOnline: true,
      lastLogin: new Date(),
    });

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role, name: user.name },
      SECRET,
      { expiresIn: '7d' },
    );

    const safe = { ...user };
    delete safe.password;
    res.json({ token, user: safe });
  } catch (error) {
    process.stderr.write(`[auth] login error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.post('/logout', verify, async (req, res) => {
  try {
    // If the client passes the FCM token it wants to un-register on this
    // device, delete it so future pushes don't target a logged-out session.
    const fcmToken = req.body && req.body.fcmToken;
    if (fcmToken) {
      await fcmTokens.deleteToken(String(fcmToken)).catch(() => {});
    }
    await users.setLoginState(req.user.id, { isOnline: false });
    res.json({ message: 'Logout สำเร็จ' });
  } catch (_) {
    res.json({ message: 'OK' });
  }
});

router.get('/me', verify, async (req, res) => {
  try {
    const user = await users.findById(req.user.id);
    if (!user) return res.status(404).json({ message: 'ไม่พบผู้ใช้' });
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/auth/fcm-token  — register or refresh an FCM token
//   body: { token: string, platform?: 'android' | 'ios' }
router.post('/fcm-token', verify, async (req, res) => {
  try {
    const token = String(req.body?.token || '').trim();
    const platform = String(req.body?.platform || 'android').toLowerCase();
    if (!token) return res.status(400).json({ message: 'missing fcm token' });
    await fcmTokens.upsert({ token, userId: req.user.id, platform });
    res.json({ message: 'OK' });
  } catch (error) {
    process.stderr.write(`[auth] fcm-token error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// DELETE /api/auth/fcm-token  — called on logout from the mobile client
router.delete('/fcm-token', verify, async (req, res) => {
  try {
    const token = String(req.body?.token || req.query?.token || '').trim();
    if (!token) return res.status(400).json({ message: 'missing fcm token' });
    await fcmTokens.deleteToken(token);
    res.json({ message: 'OK' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
