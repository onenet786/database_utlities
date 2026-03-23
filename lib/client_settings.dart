class ClientSettings {
  const ClientSettings({required this.companyName, required this.branchName});

  final String companyName;
  final String branchName;

  factory ClientSettings.fromJson(Map<String, dynamic> json) {
    return ClientSettings(
      companyName:
          (json['companyName'] ?? json['company_name'] ?? 'Database Utilities')
              .toString(),
      branchName: (json['branchName'] ?? json['branch_name'] ?? 'Main Branch')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'companyName': companyName, 'branchName': branchName};
  }
}
