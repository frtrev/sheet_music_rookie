import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';

class UnavailableMicrophone implements MicrophoneService {
  UnavailableMicrophone({this.throws = false});
  final bool throws;
  int starts = 0;
  @override
  Stream<AudioFrame> get frames => const Stream.empty();
  @override
  Future<bool> start() async {
    starts++;
    if (throws) throw StateError('Recorder unavailable');
    return false;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final throws in [false, true]) {
    test(
      'microphone ${throws ? "failure" : "denial"} preserves editing',
      () async {
        SharedPreferences.setMockInitialValues({});
        final microphone = UnavailableMicrophone(throws: throws);
        final engine = TranscriptionEngine(
          clef: ClefType.treble,
          octaveRange: OctaveRange.standard,
          microphone: microphone,
        );
        await engine.initialize();
        expect(
          microphone.starts,
          0,
          reason: 'Do not request microphone on launch',
        );
        await engine.startListening();
        expect(engine.microphoneStatus.value, MicrophoneStatus.unavailable);
        expect(engine.composition.value.microphoneActive, isFalse);
        engine.insertManualNote(0, 60, NoteValue.quarter);
        expect(engine.rawEvents, hasLength(1));
        expect(
          engine.composition.value.measures.first.notes.first.midiPitch,
          60,
        );
        await engine.dispose();
      },
    );
  }
}
