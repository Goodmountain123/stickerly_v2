import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

abstract final class StickerlySfx {
  static final List<AudioPlayer> _players = List.generate(
    5,
    (_) => AudioPlayer()..setReleaseMode(ReleaseMode.stop),
  );
  static var _nextPlayer = 0;

  static void play(String assetPath) {
    final player = _players[_nextPlayer++ % _players.length];
    final source = assetPath.startsWith('assets/')
        ? assetPath.substring('assets/'.length)
        : assetPath;
    unawaited(player.stop().then((_) => player.play(AssetSource(source))));
  }
}
