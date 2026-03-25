// models/ServiceLog.js
const mongoose = require('mongoose');

const serviceLogSchema = new mongoose.Schema({
  deviceId:     { type: mongoose.Schema.Types.ObjectId, ref: 'Device', required: true },
  technicianId: { type: mongoose.Schema.Types.ObjectId, ref: 'User',   required: true },
  type: {
    type: String,
    enum: ['refill', 'repair', 'inspection', 'installation', 'uninstall', 'other'],
    required: true,
  },
  description: { type: String, default: '' },
  notes:       { type: String, default: '' },
  photos:      [String],
}, { timestamps: true });

module.exports = mongoose.model('ServiceLog', serviceLogSchema);
