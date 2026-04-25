class DeviceModel {
  final String id;
  final String serialNumber;
  final String name;
  final String ip;
  final String mac;
  final String hardwareId;
  final String hardwareModel;
  final String? customerId;
  final String customerName;
  final String location;
  final String? groupId;
  final String status;
  final bool isOn;
  final int level;
  final int? levelMl;
  final int installedTankMl;
  final String scentName;
  final int battery;
  final double? batteryVoltage;
  final String batteryStatus;
  final bool pumpOk;
  final bool relayOk;
  final String wifiSSID;
  final String wifiIP;
  final int? signalStrength;
  final String btAddress;
  final bool btConnected;
  final List<ScheduleItem> schedule;
  final String firmwareVersion;
  final int commandVersion;
  final String? lastSensorUpdate;
  final String? lastSeenAt;
  final String createdAt;
  final String notes;

  const DeviceModel({
    required this.id,
    required this.serialNumber,
    this.name = '',
    this.ip = '',
    this.mac = '',
    this.hardwareId = '',
    this.hardwareModel = '',
    this.customerId,
    this.customerName = '',
    this.location = '',
    this.groupId,
    this.status = 'offline',
    this.isOn = false,
    this.level = 0,
    this.levelMl,
    this.installedTankMl = 1000,
    this.scentName = '',
    this.battery = 100,
    this.batteryVoltage,
    this.batteryStatus = 'unknown',
    this.pumpOk = true,
    this.relayOk = true,
    this.wifiSSID = '',
    this.wifiIP = '',
    this.signalStrength,
    this.btAddress = '',
    this.btConnected = false,
    this.schedule = const [],
    this.firmwareVersion = '',
    this.commandVersion = 0,
    this.lastSensorUpdate,
    this.lastSeenAt,
    this.createdAt = '',
    this.notes = '',
  });

  bool get isOnline => status == 'online';
  bool get isAssigned => customerId != null && customerId!.isNotEmpty;
  bool get hasName => name.isNotEmpty;
  String get displayName => name.isNotEmpty ? name : serialNumber;
  bool get isLowLevel => level < 20;
  bool get needsAttention => isLowLevel || !pumpOk || !relayOk || status == 'offline' || battery <= 20;
  int get displayMl => levelMl ?? (installedTankMl * level / 100).round();

  DeviceModel copyWith({
    String? id,
    String? serialNumber,
    String? name,
    String? ip,
    String? mac,
    String? hardwareId,
    String? hardwareModel,
    String? customerId,
    String? customerName,
    String? location,
    String? groupId,
    String? status,
    bool? isOn,
    int? level,
    int? levelMl,
    bool clearLevelMl = false,
    int? installedTankMl,
    String? scentName,
    int? battery,
    double? batteryVoltage,
    bool clearBatteryVoltage = false,
    String? batteryStatus,
    bool? pumpOk,
    bool? relayOk,
    String? wifiSSID,
    String? wifiIP,
    int? signalStrength,
    bool clearSignalStrength = false,
    String? btAddress,
    bool? btConnected,
    List<ScheduleItem>? schedule,
    String? firmwareVersion,
    int? commandVersion,
    String? lastSensorUpdate,
    String? lastSeenAt,
    String? createdAt,
    String? notes,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      serialNumber: serialNumber ?? this.serialNumber,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      hardwareId: hardwareId ?? this.hardwareId,
      hardwareModel: hardwareModel ?? this.hardwareModel,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      location: location ?? this.location,
      groupId: groupId ?? this.groupId,
      status: status ?? this.status,
      isOn: isOn ?? this.isOn,
      level: level ?? this.level,
      levelMl: clearLevelMl ? null : (levelMl ?? this.levelMl),
      installedTankMl: installedTankMl ?? this.installedTankMl,
      scentName: scentName ?? this.scentName,
      battery: battery ?? this.battery,
      batteryVoltage: clearBatteryVoltage ? null : (batteryVoltage ?? this.batteryVoltage),
      batteryStatus: batteryStatus ?? this.batteryStatus,
      pumpOk: pumpOk ?? this.pumpOk,
      relayOk: relayOk ?? this.relayOk,
      wifiSSID: wifiSSID ?? this.wifiSSID,
      wifiIP: wifiIP ?? this.wifiIP,
      signalStrength: clearSignalStrength ? null : (signalStrength ?? this.signalStrength),
      btAddress: btAddress ?? this.btAddress,
      btConnected: btConnected ?? this.btConnected,
      schedule: schedule ?? this.schedule,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      commandVersion: commandVersion ?? this.commandVersion,
      lastSensorUpdate: lastSensorUpdate ?? this.lastSensorUpdate,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
    );
  }

  DeviceModel mergeJson(Map<String, dynamic> json) {
    return copyWith(
      name: json['name']?.toString(),
      serialNumber: json['serialNumber']?.toString(),
      customerId: json.containsKey('customerId') ? json['customerId']?.toString() : null,
      customerName: json['customerName']?.toString(),
      location: json['location']?.toString(),
      status: json['status']?.toString(),
      isOn: json.containsKey('isOn') ? json['isOn'] == true : null,
      level: json['level'] is num ? (json['level'] as num).round() : null,
      levelMl: json['levelMl'] is num ? (json['levelMl'] as num).round() : null,
      installedTankMl: json['installedTankMl'] is num ? (json['installedTankMl'] as num).round() : null,
      scentName: json['scentName']?.toString(),
      battery: json['battery'] is num ? (json['battery'] as num).round() : null,
      batteryVoltage: json['batteryVoltage'] is num ? (json['batteryVoltage'] as num).toDouble() : null,
      batteryStatus: json['batteryStatus']?.toString(),
      pumpOk: json.containsKey('pumpOk') ? json['pumpOk'] == true : null,
      relayOk: json.containsKey('relayOk') ? json['relayOk'] == true : null,
      wifiSSID: json['wifiSSID']?.toString(),
      wifiIP: json['wifiIP']?.toString(),
      signalStrength: json['signalStrength'] is num ? (json['signalStrength'] as num).round() : null,
      firmwareVersion: json['firmwareVersion']?.toString(),
      commandVersion: json['commandVersion'] is num ? (json['commandVersion'] as num).round() : null,
      lastSensorUpdate: json['lastSensorUpdate']?.toString(),
      lastSeenAt: json['lastSeenAt']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) => DeviceModel(
    id: json['id']?.toString() ?? '',
    serialNumber: json['serialNumber']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    ip: json['ip']?.toString() ?? '',
    mac: json['mac']?.toString() ?? '',
    hardwareId: json['hardwareId']?.toString() ?? '',
    hardwareModel: json['hardwareModel']?.toString() ?? '',
    customerId: json['customerId']?.toString(),
    customerName: json['customerName']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    groupId: json['groupId']?.toString(),
    status: json['status']?.toString() ?? 'offline',
    isOn: json['isOn'] == true,
    level: json['level'] is num ? (json['level'] as num).round() : 0,
    levelMl: json['levelMl'] is num ? (json['levelMl'] as num).round() : null,
    installedTankMl: json['installedTankMl'] is num ? (json['installedTankMl'] as num).round() : 1000,
    scentName: json['scentName']?.toString() ?? '',
    battery: json['battery'] is num ? (json['battery'] as num).round() : 100,
    batteryVoltage: json['batteryVoltage'] is num ? (json['batteryVoltage'] as num).toDouble() : null,
    batteryStatus: json['batteryStatus']?.toString() ?? 'unknown',
    pumpOk: json['pumpOk'] != false,
    relayOk: json['relayOk'] != false,
    wifiSSID: json['wifiSSID']?.toString() ?? '',
    wifiIP: json['wifiIP']?.toString() ?? '',
    signalStrength: json['signalStrength'] is num ? (json['signalStrength'] as num).round() : null,
    btAddress: json['btAddress']?.toString() ?? '',
    btConnected: json['btConnected'] == true,
    schedule: (json['schedule'] as List?)?.map((s) => ScheduleItem.fromJson(Map<String, dynamic>.from(s))).toList() ?? const [],
    firmwareVersion: json['firmwareVersion']?.toString() ?? '',
    commandVersion: json['commandVersion'] is num ? (json['commandVersion'] as num).round() : 0,
    lastSensorUpdate: json['lastSensorUpdate']?.toString(),
    lastSeenAt: json['lastSeenAt']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
  );
}

class ScheduleItem {
  String startTime;
  String endTime;
  int workSeconds;
  int pauseSeconds;
  List<bool> activeDays;

  ScheduleItem({
    this.startTime = '08:00',
    this.endTime = '18:00',
    this.workSeconds = 30,
    this.pauseSeconds = 60,
    List<bool>? activeDays,
  }) : activeDays = activeDays ?? List.filled(7, false);

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        startTime: json['startTime']?.toString() ?? '08:00',
        endTime: json['endTime']?.toString() ?? '18:00',
        workSeconds: json['workSeconds'] is num ? (json['workSeconds'] as num).round() : 30,
        pauseSeconds: json['pauseSeconds'] is num ? (json['pauseSeconds'] as num).round() : 60,
        activeDays: (json['days'] as List?)?.map((d) => d == true).toList() ?? List.filled(7, false),
      );

  Map<String, dynamic> toJson() => {
        'startTime': startTime,
        'endTime': endTime,
        'workSeconds': workSeconds,
        'pauseSeconds': pauseSeconds,
        'days': activeDays,
      };
}
