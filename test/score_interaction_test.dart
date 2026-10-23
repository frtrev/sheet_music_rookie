import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawNoteEvent rawEvent(int midi, int durationMs, {int startTimeMs = 0}) =>
    RawNoteEvent(
      startTimeMs: startTimeMs,
      endTimeMs: startTimeMs + durationMs,
      frequencyHz: 440,
      midiPitch: midi,
      confidence: .95,
    );

class FakeMicrophoneService implements MicrophoneService {
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<AudioFrame> get frames => const Stream.empty();

  @override
  Future<bool> start() async {
    startCount++;
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('playback cursor maps elapsed time across 4/4 measures', () {
    const composition = Composition(
      clef: ClefType.treble,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(midiPitch: 60, startTick: 0, durationTicks: 1920),
          ],
        ),
        Measure(
          index: 1,
          notes: [MusicalNote(midiPitch: 62, startTick: 0, durationTicks: 480)],
        ),
      ],
    );
    expect(ScoreLayout.ticksAt(const Duration(seconds: 1), 120), 960);
    expect(ScoreLayout.durationAt(960, 120), const Duration(seconds: 1));
    expect(ScoreLayout.cursorX(composition, 0), 126);
    expect(ScoreLayout.cursorX(composition, 1920), 336);
    expect(ScoreLayout.tickAtX(composition, 336), 1920);
    expect(ScoreLayout.scoreEndTick(composition), 2400);
  });

  test('score scrolling reveals cursor movement forward and backward', () {
    final forward = ScoreLayout.scrollOffsetToRevealCursor(
      cursorX: 700,
      currentOffset: 0,
      viewportWidth: 320,
      maxScrollExtent: 600,
    );
    expect(forward, 424);

    final alreadyVisible = ScoreLayout.scrollOffsetToRevealCursor(
      cursorX: 700,
      currentOffset: forward!,
      viewportWidth: 320,
      maxScrollExtent: 600,
    );
    expect(alreadyVisible, isNull);

    final backward = ScoreLayout.scrollOffsetToRevealCursor(
      cursorX: 126,
      currentOffset: forward,
      viewportWidth: 320,
      maxScrollExtent: 600,
    );
    expect(backward, 98);
  });

  test('flat and sharp spellings use the correct staff position', () {
    final cSharp = ScoreLayout.staffStep(
      ClefType.treble,
      61,
      accidental: NoteAccidental.sharp,
    );
    final dFlat = ScoreLayout.staffStep(
      ClefType.treble,
      61,
      accidental: NoteAccidental.flat,
    );
    expect(cSharp, ScoreLayout.staffStep(ClefType.treble, 60));
    expect(dFlat, ScoreLayout.staffStep(ClefType.treble, 62));
  });

  test('cursor overwrite replaces its span and retains later notes', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.rawEvents.addAll([
      rawEvent(60, 500),
      rawEvent(62, 500),
      rawEvent(64, 500),
      rawEvent(65, 500),
    ]);

    engine.overwriteFromTick(480, [rawEvent(67, 750)]);

    expect(engine.rawEvents.map((event) => event.midiPitch), [60, 67, 64, 65]);
    expect(engine.rawEvents.map((event) => event.durationMs), [
      500,
      750,
      250,
      500,
    ]);
    expect(engine.notationCursorTick.value, 1200);
    expect(
      engine.composition.value.measures.first.notes.map(
        (note) => note.durationTicks,
      ),
      [480, 720, 240, 480],
    );
  });

  test('moving the recording cursor keeps the microphone active', () async {
    final microphone = FakeMicrophoneService();
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: microphone,
    );
    engine.rawEvents.addAll([
      rawEvent(60, 500),
      rawEvent(62, 500),
      rawEvent(64, 500),
    ]);
    await engine.initialize();

    engine.beginPunchInAt(480);
    engine.beginPunchInAt(960);

    expect(engine.isPunchingIn, isTrue);
    expect(engine.notationCursorTick.value, 960);
    expect(engine.microphoneStatus.value, MicrophoneStatus.listening);
    expect(microphone.startCount, 1);
    expect(microphone.stopCount, 0);

    await engine.dispose();
  });

  test('reselecting a note in capture mode never divides it', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.rawEvents.addAll([rawEvent(60, 2000), rawEvent(62, 500)]);

    // Taps can land at different positions within the rendered whole note.
    // They should all select its beginning without altering its duration.
    engine.beginPunchInAt(1500);
    engine.beginPunchInAt(960);
    engine.beginPunchInAt(240);

    expect(engine.notationCursorTick.value, 0);
    expect(engine.rawEvents, hasLength(2));
    expect(engine.rawEvents.first.durationMs, 2000);
    expect(
      engine.composition.value.measures.first.notes
          .where((note) => note.midiPitch == 60)
          .map((note) => note.durationTicks),
      [1920],
    );
  });

  test('tied notation fragments retain one selectable source identity', () {
    const notes = [
      MusicalNote(
        midiPitch: 60,
        startTick: 0,
        durationTicks: 960,
        sourceEventIndex: 3,
        tieToNext: true,
      ),
      MusicalNote(
        midiPitch: 60,
        startTick: 960,
        durationTicks: 480,
        sourceEventIndex: 3,
        tieFromPrevious: true,
      ),
    ];
    expect(notes.map((note) => note.sourceEventIndex).toSet(), {3});
  });

  test('cursor-selected note can change pitch spelling and duration', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(62, 500), rawEvent(62, 500)]);
    engine.notationCursorTick.value = 120;

    final lowered = engine.editNoteAtTick(120, pitchDelta: -1);
    expect(lowered, (midiPitch: 61, durationTicks: 480));
    expect(engine.rawEvents.first.midiPitch, 61);
    expect(engine.rawEvents.first.accidental, NoteAccidental.flat);
    expect(
      engine.composition.value.measures.first.notes.first.accidental,
      NoteAccidental.flat,
    );
    expect(
      engine.composition.value.measures.first.notes[1].accidental,
      NoteAccidental.natural,
    );
    expect(engine.notationCursorTick.value, 120);

    final lengthened = engine.editNoteAtTick(120, durationDelta: 1);
    expect(lengthened, (midiPitch: 61, durationTicks: 720));
    expect(engine.rawEvents.first.durationMs, 750);
    expect(engine.notationCursorTick.value, 120);
    expect(engine.eventIndexAtTick(719), 0);
    expect(engine.eventIndexAtTick(720), 1);
  });

  test(
    'manual notes preserve written pitch and preview the sounding octave',
    () {
      final engine = TranscriptionEngine(
        clef: ClefType.treble,
        octaveRange: OctaveRange.octaveUp,
        microphone: FakeMicrophoneService(),
      );

      engine.insertManualNote(0, 60, NoteValue.quarter);

      expect(engine.rawEvents.single.midiPitch, 72);
      expect(
        engine.composition.value.measures.first.notes.single.midiPitch,
        60,
      );
      final edited = engine.editNoteAtTick(0, pitchDelta: 1);
      expect(edited, (midiPitch: 73, durationTicks: 480));
      expect(
        engine.composition.value.measures.first.notes.single.midiPitch,
        61,
      );
    },
  );

  test('selected note toggles to a rest and back to the first-line note', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(67, 500)]);
    engine.notationCursorTick.value = 0;

    final rest = engine.toggleRestAtTick(0);
    expect(rest, (midiPitch: 67, durationTicks: 480, isRest: true));
    expect(engine.rawEvents.single.isRest, isTrue);
    expect(engine.composition.value.measures.first.notes.single.isRest, isTrue);
    expect(engine.notationCursorTick.value, 0);

    final note = engine.toggleRestAtTick(0);
    expect(note, (midiPitch: 64, durationTicks: 480, isRest: false));
    expect(engine.rawEvents.single.isRest, isFalse);
    expect(engine.rawEvents.single.midiPitch, 64);
    expect(engine.composition.value.measures.first.notes.single.midiPitch, 64);
    expect(engine.notationCursorTick.value, 0);
  });

  test('blank measure space inserts rests without moving the cursor', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500)]);
    engine.notationCursorTick.value = 960;

    expect(engine.eventIndexAtTick(960), isNull);
    expect(engine.canToggleRestAtTick(960), isTrue);
    final inserted = engine.toggleRestAtTick(960);

    expect(inserted, (midiPitch: 0, durationTicks: 480, isRest: true));
    expect(engine.rawEvents.map((event) => event.isRest), [false, true, true]);
    expect(
      engine.composition.value.measures.first.notes.map(
        (note) => note.startTick,
      ),
      [0, 480, 960],
    );
    expect(engine.notationCursorTick.value, 960);
  });

  test('selected note toggles its tie to the following note', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500), rawEvent(64, 500)]);
    engine.notationCursorTick.value = 0;

    expect(engine.canToggleTieAtTick(0), isTrue);
    expect(engine.isTiedAtTick(0), isFalse);
    expect(engine.toggleTieAtTick(0), isTrue);
    expect(engine.notationCursorTick.value, 0);
    expect(engine.rawEvents.first.tieToNext, isTrue);
    expect(engine.rawEvents.last.midiPitch, 60);
    final notes = engine.composition.value.measures.first.notes;
    expect(notes.first.tieToNext, isTrue);
    expect(notes.last.tieFromPrevious, isTrue);

    expect(engine.toggleTieAtTick(0), isFalse);
    expect(engine.rawEvents.first.tieToNext, isFalse);
    expect(
      engine.composition.value.measures.first.notes.first.tieToNext,
      isFalse,
    );
  });

  test('tied notes edit and preview as one sustained group', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500), rawEvent(64, 500)]);
    engine.toggleTieAtTick(0);

    expect(engine.rawEvents.map((event) => event.midiPitch), [60, 60]);
    final raised = engine.editNoteAtTick(0, pitchDelta: 1);
    expect(engine.rawEvents.map((event) => event.midiPitch), [61, 61]);
    expect(raised, (midiPitch: 61, durationTicks: 960));

    final lengthened = engine.editNoteAtTick(0, durationDelta: 1);
    expect(engine.rawEvents.map((event) => event.durationMs), [500, 750]);
    expect(lengthened, (midiPitch: 61, durationTicks: 1200));
    expect(engine.rawEvents.first.tieToNext, isTrue);
  });

  test('ties cannot be added to a rest or without a following note', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500), rawEvent(62, 500)]);

    expect(engine.canToggleTieAtTick(480), isFalse);
    engine.toggleRestAtTick(0);
    expect(engine.canToggleTieAtTick(0), isFalse);
    expect(engine.toggleTieAtTick(0), isNull);
  });
}
