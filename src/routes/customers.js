// routes/customers.js
const router   = require('express').Router();
const { managerUp, anyRole } = require('../middleware/auth');
const Customer = require('../models/Customer');

const fmt = (c) => {
  const obj = c.toObject ? c.toObject() : c;
  return { ...obj, id: obj._id.toString() };
};

// GET /api/customers
router.get('/', anyRole, async (req, res) => {
  try {
    const customers = await Customer.find().sort({ createdAt: -1 });
    res.json(customers.map(fmt));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// POST /api/customers
router.post('/', managerUp, async (req, res) => {
  try {
    const { name, contactName, contactPhone, contactEmail, address, packageQty, notes } = req.body;
    if (!name) return res.status(400).json({ message: 'กรอกชื่อลูกค้า' });

    const customer = new Customer({ name, contactName, contactPhone, contactEmail, address, packageQty, notes });
    await customer.save();
    res.status(201).json(fmt(customer));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// PUT /api/customers/:id
router.put('/:id', managerUp, async (req, res) => {
  try {
    const customer = await Customer.findByIdAndUpdate(req.params.id, req.body, { new: true });
    if (!customer) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
    res.json(fmt(customer));
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

// DELETE /api/customers/:id
router.delete('/:id', managerUp, async (req, res) => {
  try {
    const customer = await Customer.findByIdAndDelete(req.params.id);
    if (!customer) return res.status(404).json({ message: 'ไม่พบลูกค้า' });
    res.json({ message: 'ลบสำเร็จ' });
  } catch (error) {
    res.status(500).json({ message: 'เกิดข้อผิดพลาด' });
  }
});

module.exports = router;
