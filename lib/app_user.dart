import 'security_preference.dart';

class AppUser {
  const AppUser({
    this.id,
    required this.username,
    required this.role,
    this.password = '',
  });

  final int? id;
  final String username;
  final UserType role;
  final String password;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final roleValue = (json['role'] ?? 'user').toString();
    return AppUser(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      username: (json['username'] ?? '').toString(),
      role: roleValue == 'admin' ? UserType.admin : UserType.user,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role == UserType.admin ? 'admin' : 'user',
      'password': password,
    };
  }
}
