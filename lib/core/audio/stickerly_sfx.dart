import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class StickerlySfx {
  static final List<AudioPlayer> _players = List.generate(
    5,
    (_) => AudioPlayer()..setReleaseMode(ReleaseMode.stop),
  );
  static var _nextPlayer = 0;
  static var muted = false;

  static Future<void> loadPreferences() async {
    final prefs = SharedPreferencesAsync();
    muted = !(await prefs.getBool('stickerly.sound_enabled') ?? true);
  }

  static Future<void> setMuted(bool value) async {
    muted = value;
    final prefs = SharedPreferencesAsync();
    await prefs.setBool('stickerly.sound_enabled', !value);
  }

  static void play(String assetPath) {
    if (muted) return;
    final player = _players[_nextPlayer++ % _players.length];
    final source = assetPath.startsWith('assets/')
        ? assetPath.substring('assets/'.length)
        : assetPath;
    unawaited(player.stop().then((_) => player.play(AssetSource(source))));
  }
}
