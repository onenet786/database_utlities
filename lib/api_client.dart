import 'dart:convert';

import 'package:http/http.dart' as http;

import 'activity_log_entry.dart';
import 'app_session.dart';
import 'app_user.dart';
import 'client_settings.dart';
import 'database_profile.dart';
import 'operation_result.dart';
import 'security_preference.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Future<OperationResult> attach(
    DatabaseProfile profile, {
    required String actorUsername,
    required String actorRole,
  }) {
    return _postJson('/api/databases/attach', {
      ...profile.toJson(),
      'actorUsername': actorUsername,
      'actorRole': actorRole,
    });
  }

  Future<OperationResult> detach(
    DatabaseProfile profile, {
    required String actorUsername,
    required String actorRole,
  }) {
    return _postJson('/api/databases/detach', {
      ...profile.toJson(),
      'actorUsername': actorUsername,
      'actorRole': actorRole,
    });
  }

  Future<OperationResult> backupDatabase(
    DatabaseProfile profile, {
    required String backupPath,
    required String actorUsername,
    required String actorRole,
  }) {
    return _postJson('/api/databases/backup', {
      ...profile.toJson(),
      'backupPath': backupPath,
      'actorUsername': actorUsername,
      'actorRole': actorRole,
    });
  }

  Future<SecurityPreference> fetchSecurityPreference() async {
    final uri = _buildUri('/api/security/preferences');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    return SecurityPreference.fromJson(body);
  }

  Future<AppSession> login({
    required String username,
    required String password,
  }) async {
    final uri = _buildUri('/api/auth/login');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body = _decodeBody(response.body);
    if (body['success'] != true) {
      throw Exception((body['message'] as String?) ?? 'Authentication failed.');
    }
    return AppSession.fromJson(body);
  }

  Future<void> saveSecurityPreference(SecurityPreference preference) async {
    final uri = _buildUri('/api/security/preferences');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(preference.toJson()),
    );
    final body = _decodeBody(response.body);
    if (body['success'] != true) {
      throw Exception(
        (body['message'] as String?) ?? 'Could not save security preference.',
      );
    }
  }

  Future<ClientSettings> fetchClientSettings() async {
    final uri = _buildUri('/api/client/settings');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    return ClientSettings.fromJson(body);
  }

  Future<List<ClientSettings>> fetchClientSettingsList() async {
    final uri = _buildUri('/api/client/settings/list');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    return (body['clients'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ClientSettings.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<ClientSettings> saveClientSettings({
    required ClientSettings settings,
    required String actorUsername,
    required String actorRole,
  }) async {
    final uri = _buildUri('/api/client/settings');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        ...settings.toJson(),
        'actorUsername': actorUsername,
        'actorRole': actorRole,
      }),
    );
    final body = _decodeBody(response.body);
    if (body['success'] != true) {
      throw Exception(
        (body['message'] as String?) ?? 'Could not save client settings.',
      );
    }
    return ClientSettings.fromJson(
      Map<String, dynamic>.from(body['client'] as Map? ?? settings.toJson()),
    );
  }

  Future<List<AppUser>> fetchUsers({required int clientId}) async {
    final uri = _buildUri('/api/security/users?clientId=$clientId');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    return (body['users'] as List<dynamic>? ?? const [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<OperationResult> saveUser({
    required AppUser user,
    required int clientId,
    required String actorUsername,
    required String actorRole,
  }) async {
    return _postJson('/api/security/users', {
      ...user.toJson(),
      'clientId': clientId,
      'actorUsername': actorUsername,
      'actorRole': actorRole,
    });
  }

  Future<OperationResult> changeUserPassword({
    required int userId,
    required String password,
    required String actorUsername,
    required String actorRole,
  }) async {
    return _postJson('/api/security/users/password', {
      'id': userId,
      'password': password,
      'actorUsername': actorUsername,
      'actorRole': actorRole,
    });
  }

  Future<OperationResult> deleteUser(
    int id, {
    required int clientId,
    required String actorUsername,
    required String actorRole,
  }) async {
    final uri = _buildUri(
      '/api/security/users/$id?clientId=$clientId&actorUsername=${Uri.encodeQueryComponent(actorUsername)}&actorRole=${Uri.encodeQueryComponent(actorRole)}',
    );
    if (uri == null) {
      return const OperationResult(
        success: false,
        message: 'API connection is not configured.',
        command: '',
      );
    }

    try {
      final response = await http.delete(uri);
      final body = _decodeBody(response.body);
      return OperationResult(
        success: body['success'] == true,
        message: (body['message'] as String?) ?? 'Unexpected API response.',
        command: '',
      );
    } catch (error) {
      return OperationResult(
        success: false,
        message: 'Could not reach the API server. Details: $error',
        command: '',
      );
    }
  }

  Future<List<ActivityLogEntry>> fetchActivityLogs({
    required int clientId,
    int limit = 100,
  }) async {
    final uri = _buildUri('/api/activity-logs?clientId=$clientId&limit=$limit');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    return (body['logs'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ActivityLogEntry.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> logActivity({
    required int clientId,
    required String actorUsername,
    required String actorRole,
    required String actionName,
    required String actionDetails,
  }) async {
    final uri = _buildUri('/api/activity-logs');
    if (uri == null) {
      return;
    }

    await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clientId': clientId,
        'actorUsername': actorUsername,
        'actorRole': actorRole,
        'actionName': actionName,
        'actionDetails': actionDetails,
      }),
    );
  }

  Future<List<DatabaseProfile>> fetchProfiles({required int clientId}) async {
    final uri = _buildUri('/api/settings/profiles?clientId=$clientId');
    if (uri == null) {
      throw Exception('API connection is not configured.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    final items = (body['profiles'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(DatabaseProfile.fromJson)
        .toList();
    return items;
  }

  Future<OperationResult> saveProfile(
    DatabaseProfile profile, {
    required int clientId,
    required String actorUsername,
    required String actorRole,
  }) {
    return _postJson('/api/settings/profiles', {
      ...profile.toJson(),
      'clientId': clientId,
      'actorUsername': actorUsername,
      'actorRole': actorRole,
    });
  }

  Future<OperationResult> deleteProfile(
    int id, {
    required int clientId,
    required String actorUsername,
    required String actorRole,
  }) async {
    final uri = _buildUri(
      '/api/settings/profiles/$id?clientId=$clientId&actorUsername=${Uri.encodeQueryComponent(actorUsername)}&actorRole=${Uri.encodeQueryComponent(actorRole)}',
    );
    if (uri == null) {
      return const OperationResult(
        success: false,
        message: 'API connection is not configured.',
        command: '',
      );
    }

    try {
      final response = await http.delete(uri);
      final body = _decodeBody(response.body);
      return OperationResult(
        success: body['success'] == true,
        message: (body['message'] as String?) ?? 'Unexpected API response.',
        command: '',
      );
    } catch (error) {
      return OperationResult(
        success: false,
        message: 'Could not reach the API server. Details: $error',
        command: '',
      );
    }
  }

  Future<OperationResult> _postJson(
    String path,
    Map<String, dynamic> bodyJson,
  ) async {
    final uri = _buildUri(path);
    if (uri == null) {
      return const OperationResult(
        success: false,
        message: 'API connection is not configured.',
        command: '',
      );
    }

    try {
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(bodyJson),
      );

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      return OperationResult(
        success: body['success'] == true,
        message: (body['message'] as String?) ?? 'Unexpected API response.',
        command: '',
      );
    } catch (error) {
      return OperationResult(
        success: false,
        message: 'Could not reach the API server. Details: $error',
        command: '',
      );
    }
  }

  Uri? _buildUri(String path) {
    final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (normalizedBaseUrl.isEmpty) {
      return null;
    }
    return Uri.parse('$normalizedBaseUrl$path');
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return <String, dynamic>{};
  }
}
