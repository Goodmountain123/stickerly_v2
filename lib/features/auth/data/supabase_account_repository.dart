import 'dart:io';

import 'package:stickerly_v2/features/auth/domain/account_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  static const _password = 'StickerlyTest!2026';

  final SupabaseClient _client;

  @override
  Future<AccountProfile?> current() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _load(user);
  }

  @override
  Future<AccountProfile> signInTestAccount(int accountNumber) async {
    if (accountNumber != 1 && accountNumber != 2) {
      throw ArgumentError.value(accountNumber, 'accountNumber');
    }
    final response = await _client.auth.signInWithPassword(
      email: 'testaccount$accountNumber@stickerly.app',
      password: _password,
    );
    final user = response.user;
    if (user == null) throw StateError('로그인 사용자 정보가 없습니다.');
    return _load(user);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<AccountProfile> updateDisplayName(String displayName) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    await _client.rpc(
      'update_account_display_name',
      params: {'display_name': displayName},
    );
    return _load(user);
  }

  @override
  Future<AccountProfile> updateAvatarImage(String imagePath) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final file = File(imagePath);
    final extension = imagePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final storagePath =
        '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from('profile-images')
        .uploadBinary(
          storagePath,
          await file.readAsBytes(),
          fileOptions: FileOptions(
            upsert: true,
            contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );
    await _client.rpc(
      'update_account_avatar',
      params: {'avatar_path': storagePath},
    );
    return _load(user);
  }

  Future<AccountProfile> _load(User user) async {
    final profile = await _client
        .from('account_profiles')
        .select('display_name,points,avatar_storage_path')
        .eq('user_id', user.id)
        .single();
    final avatarPath = profile['avatar_storage_path'] as String?;
    final entitlements = await _client
        .from('user_pack_entitlements')
        .select('pack_id')
        .eq('user_id', user.id)
        .isFilter('revoked_at', null);
    return AccountProfile(
      userId: user.id,
      email: user.email ?? '',
      displayName: profile['display_name'] as String,
      points: (profile['points'] as num).toInt(),
      packIds: entitlements.map((row) => row['pack_id'] as String).toSet(),
      avatarUrl: avatarPath == null || avatarPath.isEmpty
          ? null
          : _client.storage.from('profile-images').getPublicUrl(avatarPath),
    );
  }
}
