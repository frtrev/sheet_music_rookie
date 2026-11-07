import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/services/score_playback_service.dart';

class PreparingPlayer implements AudioPlayer {
  final preparing = Completer<void>();
  final ready = Completer<void>();
  int plays = 0;

  @override
  Stream<void> get onPlayerComplete => const Stream.empty();
  @override
  Stream<Duration> get onPositionChanged => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    preparing.complete();
    await ready.future;
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('muting cancels a preview that is still preparing', () async {
    final player = PreparingPlayer();
    final preview = ScorePlaybackService(player: player);
    final playing = preview.playWave(Uint8List.fromList([1]));
    await player.preparing.future;
    await preview.stop(resetPosition: true);
    player.ready.complete();
    expect(await playing, isFalse);
    expect(player.plays, 0);
    expect(preview.isPlaying.value, isFalse);
    await preview.dispose();
  });
}
