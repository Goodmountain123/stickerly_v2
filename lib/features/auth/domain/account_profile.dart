class AccountProfile {
  const AccountProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.points,
    required this.packIds,
    this.avatarUrl,
  });

  final String userId;
  final String email;
  final String displayName;
  final int points;
  final Set<String> packIds;
  final String? avatarUrl;

  AccountProfile copyWith({
    String? displayName,
    int? points,
    Set<String>? packIds,
    String? avatarUrl,
  }) {
    return AccountProfile(
      userId: userId,
      email: email,
      displayName: displayName ?? this.displayName,
      points: points ?? this.points,
      packIds: packIds ?? this.packIds,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

abstract interface class AccountRepository {
  Future<AccountProfile?> current();

  Future<AccountProfile> signInTestAccount(int accountNumber);

  Future<AccountProfile> updateDisplayName(String displayName);

  Future<AccountProfile> updateAvatarImage(String imagePath);

  Future<void> signOut();
}
