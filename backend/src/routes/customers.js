// src/routes/customers.js — v6.0.0
const router = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const customers = require('../repositories/customers');
const devices = require('../repositories/devices');
const { mapCustomer } = require('../db/mappers');

router.get('/', anyRole, async (req, res) => {
  try {
    const [rows, statsMap] = await Promise.all([
      customers.listSearch(req.query.q || ''),
      customers.buildStatsMap(),
    ]);
    res.json(rows.map((row) => mapCustomer(row, statsMap.get(row.id) || {})));
  } catch (error) {
    process.stderr.write(`[customers] list error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.post('/', managerUp, async (req, res) => {
  try {
    const { name, contactName, contactPhone, contactEmail, address, packageQty, notes } = req.body;
    if (!name || !String(name).trim()) {
      return res.status(400).json({ message: 'กรอกชื่อลูกค้า' });
    }

    const normalizedPackageQty =
      packageQty === undefined || packageQty === null || packageQty === ''
        ? 1
        : Math.max(0, Number(packageQty));

    const created = await customers.create({
      name: String(name).trim(),
      contactName: contactName || '',
      contactPhone: contactPhone || '',
      contactEmail: (contactEmail || '').trim().toLowerCase(),
      address: address || '',
      packageQty: normalizedPackageQty,
      notes: notes || '',
    });
    res.status(201).json(created);
  } catch (error) {
    process.stderr.write(`[customers] create error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.put('/:id', managerUp, async (req, res) => {
  try {
    const current = await customers.findById(req.params.id);
    if (!current) {
      return res.status(404).json({ message: 'ไม่พบลูกค้า' });
    }

    const patch = { ...req.body };

    if (patch.packageQty !== undefined) {
      const currentDeviceCount = await devices.countForCustomer(current.id);
      const nextPackageQty = Math.max(0, Number(patch.packageQty));
      if (nextPackageQty < currentDeviceCount) {
        return res.status(400).json({
          message: `แพ็กเกจต้องไม่น้อยกว่าจำนวนเครื่องที่ใช้งานอยู่ (${currentDeviceCount})`,
        });
      }
      patch.packageQty = nextPackageQty;
    }

    if (patch.contactEmail !== undefined) {
      patch.contactEmail = (patch.contactEmail || '').trim().toLowerCase();
    }

    const updated = await customers.updateById(current.id, patch);
    res.json(updated);
  } catch (error) {
    process.stderr.write(`[customers] update error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

router.delete('/:id', managerUp, async (req, res) => {
  try {
    const activeDevices = await devices.countForCustomer(req.params.id);
    if (activeDevices > 0) {
      return res.status(400).json({
        message: `ยังมีเครื่อง Diffuser ผูกกับลูกค้ารายนี้อยู่ ${activeDevices} เครื่อง กรุณาย้ายหรือลบเครื่องก่อน`,
      });
    }
    const ok = await customers.deleteById(req.params.id);
    if (!ok) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    process.stderr.write(`[customers] delete error: ${error.message}\n`);
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
