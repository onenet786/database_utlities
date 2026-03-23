class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.actorUsername,
    required this.actorRole,
    required this.actionName,
    required this.actionDetails,
    required this.createdAt,
  });

  final int id;
  final String actorUsername;
  final String actorRole;
  final String actionName;
  final String actionDetails;
  final String createdAt;

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ActivityLogEntry(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}') ?? 0,
      actorUsername: (json['actorUsername'] ?? json['actor_username'] ?? '')
          .toString(),
      actorRole: (json['actorRole'] ?? json['actor_role'] ?? '').toString(),
      actionName: (json['actionName'] ?? json['action_name'] ?? '').toString(),
      actionDetails: (json['actionDetails'] ?? json['action_details'] ?? '')
          .toString(),
      createdAt: (json['createdAt'] ?? json['created_at'] ?? '').toString(),
    );
  }
}
