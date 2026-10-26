import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/note_lyric.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';

class _Microphone implements MicrophoneService {
  final controller = StreamController<AudioFrame>.broadcast(sync: true);
  @override
  Stream<AudioFrame> get frames => controller.stream;
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() => controller.close();
  void sing(int start, int duration, {double frequency = 440}) {
    for (var time = start; time < start + duration; time += 25) {
      controller.add(
        AudioFrame(
          Float64List.fromList(
            List.generate(
              2048,
              (i) => .3 * math.sin(2 * math.pi * frequency * i / 44100),
            ),
          ),
          time,
        ),
      );
    }
  }

  void silence(int start, int duration) {
    for (var time = start; time < start + duration; time += 25) {
      controller.add(AudioFrame(Float64List(2048), time));
    }
  }
}

TranscriptionEngine _engine({
  _Microphone? microphone,
  List<RawNoteEvent> events = const [],
  Composition? composition,
}) => TranscriptionEngine(
  clef: ClefType.treble,
  octaveRange: OctaveRange.standard,
  microphone: microphone ?? _Microphone(),
  initialEvents: events,
  initialComposition:
      composition ??
      Composition(
        clef: ClefType.treble,
        measures: const MeasureBuilder().build(events, 120, 4),
      ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'manual edits undo and redo with cursor positions and branching history',
    () async {
      final e = _engine();
      addTearDown(e.dispose);
      expect(e.canUndo, isFalse);
      expect(e.canRedo, isFalse);
      e.insertManualNote(0, 60, NoteValue.quarter);
      e.notationCursorTick.value = 0;
      e.editNoteAtTick(0, pitchDelta: 1);
      expect(e.rawEvents.single.midiPitch, 61);
      expect(e.undo(), isTrue);
      expect(e.rawEvents.single.midiPitch, 60);
      expect(e.notationCursorTick.value, 0);
      expect(e.redo(), isTrue);
      expect(e.rawEvents.single.midiPitch, 61);
      e.undo();
      e.toggleRestAtTick(0);
      expect(e.canRedo, isFalse);
      e.undo();
      expect(e.rawEvents.single.isRest, isFalse);
      e.undo();
      expect(e.rawEvents, isEmpty);
      expect(e.canUndo, isFalse);
      e.redo();
      expect(e.rawEvents.single.midiPitch, 60);
    },
  );
  test('ties, measure insertion, deletion, and clear are reversible', () async {
    final e = _engine();
    addTearDown(e.dispose);
    e.insertManualNote(0, 60, NoteValue.quarter);
    e.insertManualNote(480, 62, NoteValue.quarter);
    e.toggleTieAtTick(0);
    expect(e.rawEvents.last.midiPitch, 60);
    e.undo();
    expect(e.rawEvents.last.midiPitch, 62);
    expect(e.rawEvents.first.tieToNext, isFalse);
    final before = e.composition.value;
    e.insertMeasureAfterTick(0);
    e.undo();
    expect(e.composition.value.measures, before.measures);
    e.removeNoteAtTick(0);
    e.undo();
    expect(e.rawEvents.length, 2);
    e.clear();
    expect(e.rawEvents, isEmpty);
    e.undo();
    expect(e.rawEvents.length, 2);
    e.redo();
    expect(e.rawEvents, isEmpty);
  });
  test(
    'lyrics, repeat marks, signatures, octave and key survive history',
    () async {
      const lyric = NoteLyric('<lyric number="2"><text>Señor</text></lyric>');
      const events = [
        RawNoteEvent(
          startTimeMs: 0,
          endTimeMs: 500,
          frequencyHz: 261.63,
          midiPitch: 60,
          confidence: 1,
          lyrics: [lyric],
        ),
      ];
      const bar =
          '<barline location="left"><repeat direction="forward"/></barline>';
      final score = Composition(
        clef: ClefType.treble,
        measures: const MeasureBuilder().build(
          events,
          120,
          4,
          measureTemplates: const [
            Measure(index: 0, barlines: [bar]),
          ],
        ),
      );
      final e = _engine(events: events, composition: score);
      addTearDown(e.dispose);
      e.setMeasureTimeSignatureAtTick(0, beatsPerMeasure: 3, beatUnit: 4);
      e.setKeySignature(KeySignature.gMajor);
      e.setOctaveRange(OctaveRange.octaveUp);
      e.undo();
      e.undo();
      e.undo();
      expect(e.composition.value.measures, score.measures);
      expect(e.rawEvents.single.lyrics.single.text, 'Señor');
      expect(e.composition.value.measures.first.barlines, [bar]);
      e.redo();
      e.redo();
      e.redo();
      expect(e.rawEvents.single.midiPitch, 72);
      expect(e.composition.value.keySignature, KeySignature.gMajor);
      expect(e.composition.value.measures.first.beatsPerMeasure, 3);
    },
  );
  test(
    'cursor moves and non-score settings do not create undo steps',
    () async {
      final e = _engine();
      addTearDown(e.dispose);
      e.beginPunchInAt(0);
      await e.pauseListening();
      expect(e.canUndo, isFalse);
      e.removeNoteAtTick(0);
      e.toggleTieAtTick(0);
      e.setVolumes(playbackVolume: .3, metronomeVolume: .2);
      e.setMetronomeMode(MetronomeMode.single);
      expect(e.canUndo, isFalse);
      e.insertManualNote(0, 60, NoteValue.quarter);
      e.undo();
      expect(e.composition.value.playbackVolume, .3);
      expect(e.composition.value.metronomeMode, MetronomeMode.single);
    },
  );
  test(
    'recorded overwrite is one undo step and restores original notes',
    () async {
      final mic = _Microphone();
      final e = _engine(microphone: mic);
      addTearDown(e.dispose);
      e.insertManualNote(0, 60, NoteValue.whole);
      final before = e.composition.value;
      await e.startListening();
      e.beginPunchInAt(0);
      mic.sing(0, 600);
      mic.silence(600, 300);
      expect(e.canUndo, isTrue);
      await e.pauseListening();
      expect(e.rawEvents.first.midiPitch, 69);
      final recorded = e.rawEvents.toList();
      e.undo();
      expect(e.rawEvents.single.midiPitch, 60);
      expect(e.composition.value.measures, before.measures);
      expect(e.microphoneStatus.value, MicrophoneStatus.paused);
      e.redo();
      expect(e.rawEvents, recorded);
      e.undo();
      e.undo();
      expect(e.rawEvents, isEmpty);
    },
  );
  test(
    'an unfinished live note can be undone after recording is paused',
    () async {
      final mic = _Microphone();
      final e = _engine(microphone: mic);
      addTearDown(e.dispose);
      await e.startListening();
      mic.sing(0, 600);
      expect(e.canUndo, isTrue);
      await e.pauseListening();
      expect(e.rawEvents, isNotEmpty);
      e.undo();
      expect(e.rawEvents, isEmpty);
      e.redo();
      expect(e.rawEvents.first.midiPitch, 69);
    },
  );
  test(
    'successive recorded notes undo without leaving a preview behind',
    () async {
      final mic = _Microphone();
      final e = _engine(microphone: mic);
      addTearDown(e.dispose);
      await e.startListening();
      mic.sing(0, 600);
      mic.sing(600, 600, frequency: 493.883);
      mic.silence(1200, 300);
      await e.pauseListening();
      expect(e.rawEvents.length, 2);
      e.undo();
      expect(e.rawEvents.length, 1);
      expect(e.rawEvents.first.midiPitch, 69);
      expect(
        e.composition.value.measures
            .expand((m) => m.notes)
            .every((n) => n.midiPitch == 69),
        isTrue,
      );
      e.undo();
      expect(e.rawEvents, isEmpty);
      e.redo();
      e.redo();
      expect(e.rawEvents.length, 2);
      expect(e.rawEvents.last.midiPitch, 71);
    },
  );

  test('history keeps the latest 100 edits', () async {
    final e = _engine();
    addTearDown(e.dispose);
    for (var i = 0; i < 105; i++) {
      e.setTitle('Title $i');
    }
    var count = 0;
    while (e.undo()) {
      count++;
    }
    expect(count, 100);
    expect(e.composition.value.title, 'Title 4');
  });
}
