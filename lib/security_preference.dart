enum UserType { admin, user }

class SecurityPreference {
  const SecurityPreference({required this.defaultUserType});

  final UserType defaultUserType;

  factory SecurityPreference.fromJson(Map<String, dynamic> json) {
    final userTypeValue =
        (json['defaultUserType'] ?? json['default_user_type'] ?? 'admin')
            .toString();

    return SecurityPreference(
      defaultUserType: userTypeValue == 'user' ? UserType.user : UserType.admin,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'defaultUserType': defaultUserType == UserType.user ? 'user' : 'admin',
    };
  }
}
