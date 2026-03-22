import 'dart:convert';

import 'package:http/http.dart' as http;

import 'database_profile.dart';
import 'operation_result.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Future<OperationResult> attach(DatabaseProfile profile) {
    return _post('/api/databases/attach', profile);
  }

  Future<OperationResult> detach(DatabaseProfile profile) {
    return _post('/api/databases/detach', profile);
  }

  Future<String> fetchHealthMessage() async {
    final uri = _buildUri('/health');
    if (uri == null) {
      throw Exception('Enter the API base URL first.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    return (body['message'] as String?) ?? 'API is reachable.';
  }

  Future<List<DatabaseProfile>> fetchProfiles() async {
    final uri = _buildUri('/api/settings/profiles');
    if (uri == null) {
      throw Exception('Enter the API base URL first.');
    }

    final response = await http.get(uri);
    final body = _decodeBody(response.body);
    final items = (body['profiles'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(DatabaseProfile.fromJson)
        .toList();
    return items;
  }

  Future<OperationResult> saveProfile(DatabaseProfile profile) {
    return _post('/api/settings/profiles', profile);
  }

  Future<OperationResult> deleteProfile(int id) async {
    final uri = _buildUri('/api/settings/profiles/$id');
    if (uri == null) {
      return const OperationResult(
        success: false,
        message: 'Enter the API base URL first.',
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
        message: 'Could not reach API at $baseUrl. Details: $error',
        command: 'DELETE $uri',
      );
    }
  }

  Future<OperationResult> _post(String path, DatabaseProfile profile) async {
    final uri = _buildUri(path);
    if (uri == null) {
      return const OperationResult(
        success: false,
        message: 'Enter the API base URL first.',
        command: '',
      );
    }

    try {
      final response = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(profile.toJson()),
      );

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      return OperationResult(
        success: body['success'] == true,
        message: (body['message'] as String?) ?? 'Unexpected API response.',
        command: (body['command'] as String?) ?? '',
      );
    } catch (error) {
      return OperationResult(
        success: false,
        message: 'Could not reach API at $baseUrl. Details: $error',
        command: 'POST $uri',
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
