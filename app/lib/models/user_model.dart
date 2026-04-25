// lib/models/user_model.dart
class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? lastLogin;
  final bool isOnline;
  final String createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.lastLogin,
    this.isOnline = false,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'technician',
      lastLogin: json['lastLogin'],
      isOnline: json['isOnline'] ?? false,
      createdAt: json['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'email': email, 'role': role,
    'lastLogin': lastLogin, 'isOnline': isOnline, 'createdAt': createdAt,
  };

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get isTechnician => role == 'technician';
  bool get canManageUsers => role == 'admin';
  bool get canManageDevices => role == 'admin' || role == 'manager';

  String get roleDisplayTh {
    switch (role) {
      case 'admin': return 'ผู้ดูแลระบบ';
      case 'manager': return 'ผู้จัดการ';
      case 'technician': return 'ช่างเทคนิค';
      default: return role;
    }
  }

  String get roleDisplayEn {
    switch (role) {
      case 'admin': return 'Administrator';
      case 'manager': return 'Manager';
      case 'technician': return 'Technician';
      default: return role;
    }
  }
}
