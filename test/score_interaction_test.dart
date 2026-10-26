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

  test('cursor timing supports a one-beat pickup before 4/4 measures', () {
    const composition = Composition(
      clef: ClefType.treble,
      measures: [
        Measure(
          index: 0,
          beatsPerMeasure: 1,
          beatUnit: 4,
          notes: [MusicalNote(midiPitch: 59, startTick: 0, durationTicks: 480)],
        ),
        Measure(
          index: 1,
          beatsPerMeasure: 4,
          beatUnit: 4,
          notes: [
            MusicalNote(midiPitch: 67, startTick: 0, durationTicks: 1920),
          ],
        ),
      ],
    );

    expect(composition.measureStartTick(1), 480);
    expect(composition.measureIndexAtTick(479), 0);
    expect(composition.measureIndexAtTick(480), 1);
    expect(ScoreLayout.tickAtX(composition, 366), 480);
    expect(ScoreLayout.cursorX(composition, 480), 366);
    expect(ScoreLayout.scoreEndTick(composition), 2400);
  });

  test('time signature editing changes only the measure under the cursor', () {
    const initialComposition = Composition(
      clef: ClefType.treble,
      measures: [
        Measure(index: 0, beatsPerMeasure: 1, beatUnit: 4),
        Measure(index: 1, beatsPerMeasure: 4, beatUnit: 4),
      ],
    );
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      initialComposition: initialComposition,
      initialEvents: [rawEvent(59, 500), rawEvent(67, 2000)],
      microphone: FakeMicrophoneService(),
    );
    addTearDown(engine.dispose);

    engine.setMeasureTimeSignatureAtTick(480, beatsPerMeasure: 3, beatUnit: 8);

    final updated = engine.composition.value;
    expect(updated.measures.first.beatsPerMeasure, 1);
    expect(updated.measures.first.beatUnit, 4);
    expect(updated.measures[1].beatsPerMeasure, 3);
    expect(updated.measures[1].beatUnit, 8);
    expect(updated.measureStartTick(1), 480);
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

  test('automatic cursor following holds the cursor left of center', () {
    expect(
      ScoreLayout.scrollOffsetToFollowCursor(
        cursorX: 500,
        currentOffset: 0,
        viewportWidth: 320,
        maxScrollExtent: 600,
        followFraction: .4,
      ),
      372,
    );
    expect(
      ScoreLayout.scrollOffsetToFollowCursor(
        cursorX: 500,
        currentOffset: 372,
        viewportWidth: 320,
        maxScrollExtent: 600,
        followFraction: .4,
      ),
      isNull,
    );
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
    await engine.initialize(autoStart: true);

    engine.beginPunchInAt(480);
    engine.beginPunchInAt(960);

    expect(engine.isPunchingIn, isTrue);
    expect(engine.notationCursorTick.value, 960);
    expect(engine.microphoneStatus.value, MicrophoneStatus.listening);
    expect(microphone.startCount, 1);
    expect(microphone.stopCount, 0);

    await engine.dispose();
  });

  test('initializing the editor leaves every transport idle', () async {
    final microphone = FakeMicrophoneService();
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: microphone,
    );

    await engine.initialize();

    expect(engine.microphoneStatus.value, MicrophoneStatus.paused);
    expect(engine.composition.value.microphoneActive, isFalse);
    expect(microphone.startCount, 0);
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

  test('changing octave range preserves notation and transposes playback', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500), rawEvent(64, 500)]);

    engine.setOctaveRange(OctaveRange.octaveDown);
    expect(engine.rawEvents.map((event) => event.midiPitch), [48, 52]);
    expect(
      engine.composition.value.measures.first.notes.map(
        (note) => note.midiPitch,
      ),
      [60, 64],
    );

    engine.setOctaveRange(OctaveRange.standard);
    expect(engine.rawEvents.map((event) => event.midiPitch), [60, 64]);
    expect(
      engine.composition.value.measures.first.notes.map(
        (note) => note.midiPitch,
      ),
      [60, 64],
    );

    engine.setOctaveRange(OctaveRange.octaveUp);
    expect(engine.rawEvents.map((event) => event.midiPitch), [72, 76]);
    expect(
      engine.composition.value.measures.first.notes.map(
        (note) => note.midiPitch,
      ),
      [60, 64],
    );
  });

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

  test('offbeat rest insertion snaps to one complete beat', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500)]);
    engine.notationCursorTick.value = 700;
    final inserted = engine.toggleRestAtTick(700);
    expect(inserted?.durationTicks, 480);
    expect(engine.rawEvents.length, 2);
    expect(engine.rawEvents.last.isRest, isTrue);
    expect(engine.rawEvents.last.durationMs, 500);
    expect(engine.composition.value.measures.first.notes.last.startTick, 480);
    expect(engine.notationCursorTick.value, 480);
    engine.undo();
    expect(engine.rawEvents.length, 1);
    expect(engine.notationCursorTick.value, 700);
    engine.redo();
    expect(engine.rawEvents.length, 2);
    expect(engine.notationCursorTick.value, 480);
  });

  test('rest beat duration follows eighth and half-note time signatures', () {
    for (final (beats, unit, ticks, milliseconds) in [
      (6, 8, 240, 250),
      (2, 2, 960, 1000),
    ]) {
      final engine = TranscriptionEngine(
        clef: ClefType.treble,
        octaveRange: OctaveRange.standard,
        microphone: FakeMicrophoneService(),
        initialComposition: Composition(
          clef: ClefType.treble,
          beatsPerMeasure: beats,
          beatUnit: unit,
        ),
      );
      engine.overwriteFromTick(0, [rawEvent(60, milliseconds)]);
      final cursor = ticks + ticks ~/ 3;
      final result = engine.toggleRestAtTick(cursor);
      expect(result?.durationTicks, ticks);
      expect(engine.rawEvents.length, 2);
      expect(engine.rawEvents.last.durationMs, milliseconds);
      expect(engine.notationCursorTick.value, ticks);
    }
  });

  test('rest snaps within the measure and uses local meter changes', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
      initialComposition: const Composition(
        clef: ClefType.treble,
        measures: [
          Measure(index: 0, beatsPerMeasure: 3, beatUnit: 8),
          Measure(index: 1, beatsPerMeasure: 2, beatUnit: 2),
        ],
      ),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 750)]);
    final result = engine.toggleRestAtTick(1100);
    expect(result?.durationTicks, 960);
    expect(engine.notationCursorTick.value, 720);
    expect(engine.rawEvents.length, 2);
    final empty = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    empty.toggleRestAtTick(1900);
    expect(empty.notationCursorTick.value, 1440);
    expect(
      empty.composition.value.measures.first.notes.last.durationTicks,
      480,
    );
    expect(empty.composition.value.measures.first.notes.last.startTick, 1440);
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

  test(
    'shortening a quarter in 2/4 leaves an eighth rest before the next note',
    () {
      final engine = TranscriptionEngine(
        clef: ClefType.treble,
        octaveRange: OctaveRange.standard,
        microphone: FakeMicrophoneService(),
        initialComposition: const Composition(
          clef: ClefType.treble,
          beatsPerMeasure: 2,
        ),
      );
      engine.overwriteFromTick(0, [rawEvent(60, 500), rawEvent(64, 500)]);
      engine.notationCursorTick.value = 0;
      final result = engine.editNoteAtTick(0, durationDelta: -1);
      expect(result, (midiPitch: 60, durationTicks: 240));
      final notes = engine.composition.value.measures.first.notes;
      expect(notes.map((n) => n.durationTicks), [240, 240, 480]);
      expect(notes.map((n) => n.isRest), [false, true, false]);
      expect(notes.map((n) => n.startTick), [0, 240, 480]);
      expect(engine.rawEvents.last.startTimeMs, 500);
      engine.undo();
      expect(engine.rawEvents.length, 2);
      engine.redo();
      expect(engine.rawEvents.length, 3);
      expect(engine.composition.value.measures.first.notes.last.startTick, 480);
      engine.editNoteAtTick(0, durationDelta: 1);
      expect(engine.rawEvents.map((e) => e.isRest), [false, true, false]);
      expect(engine.composition.value.measures.first.notes.last.startTick, 480);
      engine.editNoteAtTick(0, durationDelta: 1);
      expect(engine.rawEvents.length, 2);
      expect(engine.rawEvents.last.startTimeMs, 500);
    },
  );

  test('repeated shortening keeps the following note and bar in place', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 2000), rawEvent(64, 500)]);
    engine.editNoteAtTick(0, durationDelta: -1);
    engine.editNoteAtTick(0, durationDelta: -1);
    expect(engine.composition.value.measures[1].notes.first.midiPitch, 64);
    expect(engine.composition.value.measures[1].notes.first.startTick, 0);
    expect(engine.rawEvents.last.startTimeMs, 2000);
    expect(
      engine.composition.value.measures.first.notes.first.durationTicks,
      480,
    );
  });

  test('note button inserts at a beat and toggles an existing note or rest in one history step', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    final added = engine.toggleNoteAtTick(100);
    expect(added, (midiPitch: 64, durationTicks: 480, isRest: false));
    expect(engine.rawEvents.single.isRest, isFalse);
    expect(engine.notationCursorTick.value, 0);
    engine.undo();
    expect(engine.rawEvents, isEmpty);
    expect(engine.canUndo, isFalse);
    engine.redo();
    expect(engine.rawEvents.single.midiPitch, 64);
    expect(engine.toggleNoteAtTick(0)?.isRest, isTrue);
    expect(engine.toggleRestAtTick(0)?.isRest, isFalse);
    expect(engine.toggleRestAtTick(0)?.isRest, isTrue);
    expect(engine.toggleNoteAtTick(0)?.isRest, isFalse);
  });

  test('fixed note and rest actions never toggle back on repeated presses', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    expect(engine.writeNoteAtTick(100)?.isRest, isFalse);
    final revision = engine.historyRevision.value;
    final original = engine.rawEvents.single;
    final sounded = engine.writeNoteAtTick(0);
    expect(sounded, (midiPitch: 64, durationTicks: 480, isRest: false));
    expect(engine.rawEvents.single, same(original));
    expect(engine.historyRevision.value, revision);
    expect(engine.writeRestAtTick(0)?.isRest, isTrue);
    final restRevision = engine.historyRevision.value;
    expect(engine.writeRestAtTick(0)?.isRest, isTrue);
    expect(engine.historyRevision.value, restRevision);
    expect(engine.writeNoteAtTick(0)?.isRest, isFalse);
    engine.undo();
    expect(engine.rawEvents.single.isRest, isTrue);
    engine.writeRestAtTick(0);
    expect(engine.canRedo, isTrue);
    engine.redo();
    expect(engine.rawEvents.single.isRest, isFalse);
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

  test('removing a selected tied note removes its complete musical group', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [
      rawEvent(60, 500),
      rawEvent(62, 500),
      rawEvent(64, 500),
    ]);
    engine.toggleTieAtTick(0);

    expect(engine.removeNoteAtTick(480), isTrue);
    expect(engine.rawEvents.map((event) => event.midiPitch), [64]);
    expect(engine.notationCursorTick.value, 0);
    expect(engine.removeNoteAtTick(960), isFalse);
  });

  test('inserting a measure uses the bar boundary instead of cursor tick', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [
      for (var index = 0; index < 8; index++) rawEvent(60 + index, 500),
    ]);
    engine.notationCursorTick.value = 600;

    expect(engine.insertMeasureAfterTick(600), 1920);
    expect(engine.notationCursorTick.value, 600);
    expect(engine.rawEvents.map((event) => event.midiPitch), [
      60,
      61,
      62,
      63,
      0,
      64,
      65,
      66,
      67,
    ]);
    expect(engine.rawEvents[4].isRest, isTrue);
    expect(engine.rawEvents[4].durationMs, 2000);
    expect(
      engine.composition.value.measures[1].notes.single.durationTicks,
      1920,
    );
    expect(engine.composition.value.measures[2].notes.first.midiPitch, 64);
  });

  test('inserting after a partial measure fills it before the blank bar', () {
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: FakeMicrophoneService(),
    );
    engine.overwriteFromTick(0, [rawEvent(60, 500)]);

    engine.insertMeasureAfterTick(0);

    expect(
      engine.composition.value.measures[0].notes.fold<int>(
        0,
        (sum, note) => sum + note.durationTicks,
      ),
      1920,
    );
    expect(
      engine.composition.value.measures[1].notes.single,
      isA<MusicalNote>()
          .having((note) => note.isRest, 'isRest', isTrue)
          .having((note) => note.durationTicks, 'durationTicks', 1920),
    );
  });
}
