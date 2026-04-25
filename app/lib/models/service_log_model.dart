// lib/models/service_log_model.dart
class ServiceLogModel {
  final String id;
  final String deviceId;
  final String technicianId;
  final String? taskId;
  final String type;          // refill, repair, inspection, installation, uninstall, other
  final String description;
  final String notes;
  final List<String> photos;
  final String createdAt;
  // enriched
  final String deviceName;
  final String deviceSerial;
  final String customerName;
  final String technicianName;

  ServiceLogModel({
    required this.id, required this.deviceId, required this.technicianId,
    this.taskId, required this.type, this.description = '', this.notes = '',
    this.photos = const [], required this.createdAt,
    this.deviceName = '', this.deviceSerial = '', this.customerName = '', this.technicianName = '',
  });

  factory ServiceLogModel.fromJson(Map<String, dynamic> json) {
    return ServiceLogModel(
      id: json['id']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      technicianId: json['technicianId']?.toString() ?? '',
      taskId: json['taskId'],
      type: json['type'] ?? 'other',
      description: json['description'] ?? '',
      notes: json['notes'] ?? '',
      photos: List<String>.from(json['photos'] ?? []),
      createdAt: json['createdAt'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceSerial: json['deviceSerial'] ?? '',
      customerName: json['customerName'] ?? '',
      technicianName: json['technicianName'] ?? '',
    );
  }

  String get typeDisplayTh {
    switch (type) {
      case 'refill': return 'เติมน้ำหอม';
      case 'repair': return 'ซ่อม';
      case 'inspection': return 'ตรวจเช็ค';
      case 'installation': return 'ติดตั้ง';
      case 'uninstall': return 'ถอดเครื่อง';
      default: return 'อื่นๆ';
    }
  }

  String get typeDisplayEn {
    switch (type) {
      case 'refill': return 'Refill';
      case 'repair': return 'Repair';
      case 'inspection': return 'Inspection';
      case 'installation': return 'Installation';
      case 'uninstall': return 'Uninstall';
      default: return 'Other';
    }
  }
}
