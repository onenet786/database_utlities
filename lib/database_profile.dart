enum AuthenticationMode { windows, sqlServer }

class DatabaseProfile {
  DatabaseProfile({
    this.id,
    required this.server,
    required this.databaseName,
    required this.mdfPath,
    required this.authenticationMode,
    this.ldfPath = '',
    this.username = '',
    this.password = '',
  });

  final int? id;
  final String server;
  final String databaseName;
  final String mdfPath;
  final String ldfPath;
  final AuthenticationMode authenticationMode;
  final String username;
  final String password;

  factory DatabaseProfile.fromJson(Map<String, dynamic> json) {
    final authenticationModeValue =
        (json['authenticationMode'] ?? json['authentication_mode'] ?? 'windows').toString();

    return DatabaseProfile(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id'] ?? ''}'),
      server: (json['server'] ?? '').toString(),
      databaseName: (json['databaseName'] ?? json['database_name'] ?? '').toString(),
      mdfPath: (json['mdfPath'] ?? json['mdf_path'] ?? '').toString(),
      ldfPath: (json['ldfPath'] ?? json['ldf_path'] ?? '').toString(),
      authenticationMode: authenticationModeValue == 'sqlServer'
          ? AuthenticationMode.sqlServer
          : AuthenticationMode.windows,
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'server': server,
      'databaseName': databaseName,
      'mdfPath': mdfPath,
      'ldfPath': ldfPath,
      'authenticationMode':
          authenticationMode == AuthenticationMode.windows ? 'windows' : 'sqlServer',
      'username': username,
      'password': password,
    };
  }

  DatabaseProfile copyWith({
    int? id,
    String? server,
    String? databaseName,
    String? mdfPath,
    String? ldfPath,
    AuthenticationMode? authenticationMode,
    String? username,
    String? password,
  }) {
    return DatabaseProfile(
      id: id ?? this.id,
      server: server ?? this.server,
      databaseName: databaseName ?? this.databaseName,
      mdfPath: mdfPath ?? this.mdfPath,
      ldfPath: ldfPath ?? this.ldfPath,
      authenticationMode: authenticationMode ?? this.authenticationMode,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}
