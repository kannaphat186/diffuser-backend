// src/db/mappers.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// All Postgres rows come back snake_case. The Flutter app and the
// v5.x API contract expect camelCase with an `id` string field.
// These mappers are the single place that translation happens.
//
// Changing a column? Change it here too. Nowhere else in the code
// should speak snake_case.
// ─────────────────────────────────────────────────────────────

function mapUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    role: row.role,
    lastLogin: row.last_login,
    isOnline: row.is_online,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapUserWithPassword(row) {
  if (!row) return null;
  return { ...mapUser(row), password: row.password };
}

function mapCustomer(row, stats = {}) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    contactName: row.contact_name,
    contactPhone: row.contact_phone,
    contactEmail: row.contact_email,
    address: row.address,
    packageQty: row.package_qty,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deviceCount: stats.deviceCount || 0,
    onlineCount: stats.onlineCount || 0,
    alertCount: stats.alertCount || 0,
  };
}

function mapDevice(row, customerName = '') {
  if (!row) return null;
  return {
    id: row.id,
    serialNumber: row.serial_number,
    name: row.name,
    ip: row.ip,
    mac: row.mac,
    hardwareId: row.hardware_id,
    hardwareModel: row.hardware_model,
    customerId: row.customer_id,
    customerName,
    location: row.location,
    groupId: row.group_id,
    status: row.status,
    isOn: row.is_on,
    level: row.level,
    levelMl: row.level_ml,
    installedTankMl: row.installed_tank_ml,
    scentName: row.scent_name,
    battery: row.battery,
    batteryVoltage: row.battery_voltage,
    batteryStatus: row.battery_status,
    pumpOk: row.pump_ok,
    relayOk: row.relay_ok,
    wifiSSID: row.wifi_ssid,
    wifiIP: row.wifi_ip,
    signalStrength: row.signal_strength,
    btAddress: row.bt_address,
    btConnected: row.bt_connected,
    schedule: Array.isArray(row.schedule) ? row.schedule : [],
    firmwareVersion: row.firmware_version,
    deviceToken: row.device_token,
    claimCode: row.claim_code,
    commandVersion: row.command_version,
    lastCommandAt: row.last_command_at,
    provisionedAt: row.provisioned_at,
    lastSensorUpdate: row.last_sensor_update,
    lastSeenAt: row.last_seen_at,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapServiceLog(row, extras = {}) {
  if (!row) return null;
  return {
    id: row.id,
    deviceId: row.device_id,
    technicianId: row.technician_id,
    type: row.type,
    description: row.description,
    notes: row.notes,
    photos: Array.isArray(row.photos) ? row.photos : [],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deviceName: extras.deviceName || '',
    deviceSerial: extras.deviceSerial || '',
    customerName: extras.customerName || '',
    technicianName: extras.technicianName || '',
  };
}

function mapNotification(row, userId) {
  if (!row) return null;
  const targetRoles = Array.isArray(row.target_roles) ? row.target_roles : [];
  return {
    id: row.id,
    title: row.title,
    message: row.message,
    type: row.type,
    deviceId: row.device_id,
    deviceName: row.device_name,
    targetRoles,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    // isRead is derived per-user from notification_reads via a LEFT JOIN.
    // Repositories that SELECT a "read_at" column populate it; plain SELECTs
    // fall back to row.read_by_user being undefined → isRead=false.
    isRead: row.read_at !== undefined && row.read_at !== null,
  };
}

// Column allow-list used by device update helpers. Keeps the SET clause
// deterministic and stops arbitrary fields from leaking into SQL.
const DEVICE_WRITABLE_COLUMNS = Object.freeze({
  serialNumber:     'serial_number',
  name:             'name',
  ip:               'ip',
  mac:              'mac',
  hardwareId:       'hardware_id',
  hardwareModel:    'hardware_model',
  customerId:       'customer_id',
  location:         'location',
  groupId:          'group_id',
  status:           'status',
  isOn:             'is_on',
  level:            'level',
  levelMl:          'level_ml',
  installedTankMl:  'installed_tank_ml',
  scentName:        'scent_name',
  battery:          'battery',
  batteryVoltage:   'battery_voltage',
  batteryStatus:    'battery_status',
  pumpOk:           'pump_ok',
  relayOk:          'relay_ok',
  wifiSSID:         'wifi_ssid',
  wifiIP:           'wifi_ip',
  signalStrength:   'signal_strength',
  btAddress:        'bt_address',
  btConnected:      'bt_connected',
  schedule:         'schedule',
  firmwareVersion:  'firmware_version',
  deviceToken:      'device_token',
  claimCode:        'claim_code',
  commandVersion:   'command_version',
  lastCommandAt:    'last_command_at',
  provisionedAt:    'provisioned_at',
  lastSensorUpdate: 'last_sensor_update',
  lastSeenAt:       'last_seen_at',
  notes:            'notes',
});

function buildUpdateSql(table, updates, columnMap, idColumn = 'id') {
  const cols = [];
  const vals = [];
  let n = 1;
  for (const [jsKey, val] of Object.entries(updates)) {
    const sqlCol = columnMap[jsKey];
    if (!sqlCol) continue;
    cols.push(`${sqlCol} = $${n++}`);
    // Schedule + photos are JSONB.
    if (sqlCol === 'schedule' || sqlCol === 'photos' || sqlCol === 'target_roles') {
      vals.push(JSON.stringify(val));
    } else {
      vals.push(val);
    }
  }
  if (!cols.length) return null;
  return {
    sql: `UPDATE ${table} SET ${cols.join(', ')} WHERE ${idColumn} = $${n} RETURNING *`,
    values: [...vals, null],  // caller fills in the id as the last param
  };
}

module.exports = {
  mapUser,
  mapUserWithPassword,
  mapCustomer,
  mapDevice,
  mapServiceLog,
  mapNotification,
  DEVICE_WRITABLE_COLUMNS,
  buildUpdateSql,
};
