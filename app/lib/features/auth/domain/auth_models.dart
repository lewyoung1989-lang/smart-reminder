class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        accessExpiresIn: json['access_expires_in'] as int,
      );

  final String accessToken;
  final String refreshToken;
  final int accessExpiresIn;

  @override
  bool operator ==(Object other) =>
      other is AuthTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.accessExpiresIn == accessExpiresIn;

  @override
  int get hashCode => Object.hash(
        accessToken,
        refreshToken,
        accessExpiresIn,
      );
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.phoneMasked,
    required this.phoneVerified,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'].toString(),
        phoneMasked: json['phone_masked'] as String,
        phoneVerified: json['phone_verified'] as bool,
      );

  final String id;
  final String phoneMasked;
  final bool phoneVerified;
}

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        tokens: AuthTokens.fromJson(json),
      );

  final AuthUser user;
  final AuthTokens tokens;
}
