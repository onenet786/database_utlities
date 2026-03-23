class ClientSettings {
  const ClientSettings({
    this.id,
    required this.companyName,
    required this.branchName,
  });

  final int? id;
  final String companyName;
  final String branchName;

  factory ClientSettings.fromJson(Map<String, dynamic> json) {
    return ClientSettings(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id'] ?? ''}'),
      companyName:
          (json['companyName'] ?? json['company_name'] ?? 'Database Utilities')
              .toString(),
      branchName: (json['branchName'] ?? json['branch_name'] ?? 'Main Branch')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'companyName': companyName, 'branchName': branchName};
  }
}
