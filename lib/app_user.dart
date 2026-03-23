import 'security_preference.dart';

class AppUser {
  const AppUser({
    this.id,
    required this.username,
    required this.role,
    this.clientId,
    this.clientName = '',
    this.branchName = '',
    this.password = '',
  });

  final int? id;
  final String username;
  final UserType role;
  final int? clientId;
  final String clientName;
  final String branchName;
  final String password;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final roleValue = (json['role'] ?? 'user').toString();
    return AppUser(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      username: (json['username'] ?? '').toString(),
      role: roleValue == 'admin' ? UserType.admin : UserType.user,
      clientId: json['clientId'] is int
          ? json['clientId'] as int
          : int.tryParse('${json['clientId'] ?? json['client_id'] ?? ''}'),
      clientName: (json['clientName'] ?? json['client_name'] ?? '').toString(),
      branchName: (json['branchName'] ?? json['branch_name'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role == UserType.admin ? 'admin' : 'user',
      'clientId': clientId,
      'password': password,
    };
  }
}
