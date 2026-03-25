// models/Customer.js
const mongoose = require('mongoose');

const customerSchema = new mongoose.Schema({
  name:         { type: String, required: true },
  contactName:  { type: String, default: '' },
  contactPhone: { type: String, default: '' },
  contactEmail: { type: String, default: '' },
  address:      { type: String, default: '' },
  packageQty:   { type: Number, default: 0 },
  notes:        { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('Customer', customerSchema);
