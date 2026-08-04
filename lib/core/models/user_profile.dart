class UserProfile {
  const UserProfile({required this.fullName, required this.email, this.gender});

  final String fullName;
  final String email;
  final String? gender;

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.first.isEmpty ? 'there' : parts.first;
  }

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'email': email,
    'gender': gender,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    fullName: json['fullName'] as String? ?? '',
    email: json['email'] as String? ?? '',
    gender: json['gender'] as String?,
  );
}
