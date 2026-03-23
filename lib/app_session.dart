import 'client_settings.dart';
import 'security_preference.dart';

class AppSession {
  const AppSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.clientId,
    required this.clientSettings,
  });

  final int userId;
  final String username;
  final UserType role;
  final int clientId;
  final ClientSettings clientSettings;

  factory AppSession.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from(json['user'] as Map? ?? const {});
    final roleValue = (user['role'] ?? 'user').toString();
    return AppSession(
      userId: user['id'] is int
          ? user['id'] as int
          : int.tryParse('${user['id'] ?? ''}') ?? 0,
      username: (user['username'] ?? '').toString(),
      role: roleValue == 'admin' ? UserType.admin : UserType.user,
      clientId: user['clientId'] is int
          ? user['clientId'] as int
          : int.tryParse('${user['clientId'] ?? user['client_id'] ?? ''}') ?? 1,
      clientSettings: ClientSettings.fromJson(
        Map<String, dynamic>.from(json['clientSettings'] as Map? ?? const {}),
      ),
    );
  }
}
