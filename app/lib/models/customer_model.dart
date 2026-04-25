class CustomerModel {
  final String id;
  final String name;
  final String contactName;
  final String contactPhone;
  final String contactEmail;
  final String address;
  final int packageQty;
  final String notes;
  final int deviceCount;
  final int onlineCount;
  final int alertCount;
  final String createdAt;

  CustomerModel({required this.id, required this.name, this.contactName = '', this.contactPhone = '', this.contactEmail = '', this.address = '', this.packageQty = 0, this.notes = '', this.deviceCount = 0, this.onlineCount = 0, this.alertCount = 0, this.createdAt = ''});

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
    id: json['id'] ?? '', name: json['name'] ?? '', contactName: json['contactName'] ?? '', contactPhone: json['contactPhone'] ?? '',
    contactEmail: json['contactEmail'] ?? '', address: json['address'] ?? '', packageQty: json['packageQty'] ?? 0, notes: json['notes'] ?? '',
    deviceCount: json['deviceCount'] ?? 0, onlineCount: json['onlineCount'] ?? 0, alertCount: json['alertCount'] ?? 0, createdAt: json['createdAt'] ?? '',
  );
}
