enum AuthenticationMode { windows, sqlServer }

enum DatabaseAttachmentStatus { attached, detached, unknown }

class DatabaseProfile {
  DatabaseProfile({
    this.id,
    required this.server,
    required this.databaseName,
    required this.mdfPath,
    required this.authenticationMode,
    this.attachmentStatus = DatabaseAttachmentStatus.unknown,
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
  final DatabaseAttachmentStatus attachmentStatus;

  factory DatabaseProfile.fromJson(Map<String, dynamic> json) {
    final authenticationModeValue =
        (json['authenticationMode'] ?? json['authentication_mode'] ?? 'windows')
            .toString();
    final attachmentStatusValue =
        (json['attachmentStatus'] ?? json['attachment_status'] ?? 'unknown')
            .toString();

    return DatabaseProfile(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      server: (json['server'] ?? '').toString(),
      databaseName: (json['databaseName'] ?? json['database_name'] ?? '')
          .toString(),
      mdfPath: (json['mdfPath'] ?? json['mdf_path'] ?? '').toString(),
      ldfPath: (json['ldfPath'] ?? json['ldf_path'] ?? '').toString(),
      authenticationMode: authenticationModeValue == 'sqlServer'
          ? AuthenticationMode.sqlServer
          : AuthenticationMode.windows,
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      attachmentStatus: switch (attachmentStatusValue) {
        'attached' => DatabaseAttachmentStatus.attached,
        'detached' => DatabaseAttachmentStatus.detached,
        _ => DatabaseAttachmentStatus.unknown,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'server': server,
      'databaseName': databaseName,
      'mdfPath': mdfPath,
      'ldfPath': ldfPath,
      'authenticationMode': authenticationMode == AuthenticationMode.windows
          ? 'windows'
          : 'sqlServer',
      'username': username,
      'password': password,
      'attachmentStatus': switch (attachmentStatus) {
        DatabaseAttachmentStatus.attached => 'attached',
        DatabaseAttachmentStatus.detached => 'detached',
        DatabaseAttachmentStatus.unknown => 'unknown',
      },
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
    DatabaseAttachmentStatus? attachmentStatus,
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
      attachmentStatus: attachmentStatus ?? this.attachmentStatus,
    );
  }
}
