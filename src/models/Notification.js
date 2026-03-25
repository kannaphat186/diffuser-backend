// models/Notification.js
const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
  title:       { type: String, required: true },
  message:     { type: String, required: true },
  type:        { type: String, default: 'info' },
  deviceId:    { type: mongoose.Schema.Types.ObjectId, ref: 'Device', default: null },
  targetRoles: [String],
  isRead:      { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model('Notification', notificationSchema);
