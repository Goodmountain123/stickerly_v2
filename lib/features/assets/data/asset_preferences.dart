import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AssetPreferences {
  AssetPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _hiddenPackIdsKey = 'stickerly.hidden_pack_ids';

  final SharedPreferencesAsync _preferences;

  Future<Set<String>> loadHiddenPackIds() async {
    final raw = await _preferences.getString(_hiddenPackIdsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final values = (jsonDecode(raw) as List<dynamic>).cast<String>();
      return values.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveHiddenPackIds(Set<String> hiddenPackIds) async {
    final sorted = hiddenPackIds.toList()..sort();
    await _preferences.setString(_hiddenPackIdsKey, jsonEncode(sorted));
  }
}
