class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.nickname,
    required this.phoneMasked,
    required this.role,
    required this.isSelf,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        phoneMasked: json['phone_masked'] as String,
        role: json['role'] as String,
        isSelf: json['is_self'] as bool,
      );

  final String id;
  final String nickname;
  final String phoneMasked;
  final String role;
  final bool isSelf;
}

class FamilyInfo {
  FamilyInfo({
    required this.id,
    required this.name,
    required this.role,
    required List<FamilyMember> members,
  }) : members = List.unmodifiable(members);

  factory FamilyInfo.fromJson(Map<String, dynamic> json) => FamilyInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        members: (json['members'] as List<dynamic>)
            .map(
                (value) => FamilyMember.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );

  final String id;
  final String name;
  final String role;
  final List<FamilyMember> members;
  bool get isAdmin => role == 'admin';
}

class FamilyInvitation {
  const FamilyInvitation({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}
