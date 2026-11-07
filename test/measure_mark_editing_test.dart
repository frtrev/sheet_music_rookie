import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure_marks.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/music/performance_plan.dart';
import 'package:sheet_music_rookie/services/composition_storage_service.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';
import 'package:xml/xml.dart';

class _SilentMicrophone implements MicrophoneService {
  @override
  Stream<AudioFrame> get frames => const Stream.empty();
  @override
  Future<bool> start() async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

TranscriptionEngine makeEngine() {
  final events = [
    for (var i = 0; i < 5; i++)
      RawNoteEvent(
        startTimeMs: i * 500,
        endTimeMs: (i + 1) * 500,
        frequencyHz: 261.6,
        midiPitch: 60 + i,
        confidence: 1,
      ),
  ];
  return TranscriptionEngine(
    clef: ClefType.treble,
    octaveRange: OctaveRange.standard,
    microphone: _SilentMicrophone(),
    initialEvents: events,
    initialComposition: Composition(
      clef: ClefType.treble,
      beatsPerMeasure: 1,
      measures: const MeasureBuilder().build(
        events,
        120,
        1,
        addTrailingMeasure: false,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repeat sides and volta cycles are independent and coexist', () {
    var marks = const MeasureMarks([]);
    for (final edge in MeasureEdge.values) {
      marks = MeasureMarks(marks.toggleRepeat(edge));
      expect(marks.hasRepeat(edge), isTrue);
      for (final expected in ['1', '2', '3', null]) {
        marks = MeasureMarks(marks.cycleVolta(edge));
        expect(marks.voltaNumber(edge), expected);
        expect(marks.hasRepeat(edge), isTrue);
      }
    }
    marks = MeasureMarks(marks.toggleRepeat(MeasureEdge.left));
    expect(marks.hasRepeat(MeasureEdge.left), isFalse);
    expect(marks.hasRepeat(MeasureEdge.right), isTrue);
    marks = MeasureMarks(marks.toggleRepeat(MeasureEdge.right));
    expect(marks.barlines, isEmpty);
  });

  test('editing preserves imported styles, attributes and unrelated marks', () {
    const left =
        '<barline location="left" color="#123456"><bar-style>heavy-light</bar-style><segno/></barline>';
    const right =
        '<barline location="right"><bar-style>light-heavy</bar-style><ending number="1" type="stop" color="#abcdef"/><repeat direction="backward" times="3"/></barline>';
    var marks = const MeasureMarks([left, right]);
    marks = MeasureMarks(marks.cycleVolta(MeasureEdge.right));
    expect(marks.barlines.first, left);
    final bar = XmlDocument.parse(marks.barlines.last).rootElement;
    expect(bar.getElement('ending')!.getAttribute('number'), '2');
    expect(bar.getElement('ending')!.getAttribute('color'), '#abcdef');
    expect(bar.getElement('repeat')!.getAttribute('times'), '3');
    expect(bar.getElement('bar-style')!.innerText, 'light-heavy');
    marks = MeasureMarks(marks.toggleRepeat(MeasureEdge.right));
    expect(marks.voltaNumber(MeasureEdge.right), '2');
    expect(marks.hasRepeat(MeasureEdge.right), isFalse);
    marks = MeasureMarks(marks.toggleRepeat(MeasureEdge.left));
    expect(
      XmlDocument.parse(marks.barlines.first).rootElement.getElement('segno'),
      isNotNull,
    );
  });

  test(
    'measure edits target the cursor measure, retain notes and undo/redo',
    () async {
      final engine = makeEngine();
      addTearDown(engine.dispose);
      final before = engine.composition.value;
      engine.editMeasureMarkAtTick(600, edge: MeasureEdge.left);
      expect(engine.composition.value.measures.first.barlines, isEmpty);
      expect(
        MeasureMarks(engine.composition.value.measures[1].barlines)
            .hasRepeat(MeasureEdge.left),
        isTrue,
      );
      expect(
        engine.composition.value.measures[1].notes,
        same(before.measures[1].notes),
      );
      engine.undo();
      expect(engine.composition.value.measures[1].barlines, isEmpty);
      engine.redo();
      expect(
        MeasureMarks(engine.composition.value.measures[1].barlines)
            .hasRepeat(MeasureEdge.left),
        isTrue,
      );
      engine.setLyricAtTick(480, '1', 'Keep the marks');
      expect(
        MeasureMarks(engine.composition.value.measures[1].barlines)
            .hasRepeat(MeasureEdge.left),
        isTrue,
      );
    },
  );

  test(
    'authored three endings play correctly and survive MXL reopen',
    () async {
      final engine = makeEngine();
      addTearDown(engine.dispose);
      engine.editMeasureMarkAtTick(0, edge: MeasureEdge.left);
      engine.editMeasureMarkAtTick(960, edge: MeasureEdge.right);
      for (var number = 1; number <= 3; number++) {
        for (var press = 0; press < number; press++) {
          for (final edge in MeasureEdge.values) {
            engine.editMeasureMarkAtTick(
              (number + 1) * 480,
              edge: edge,
              volta: true,
            );
          }
        }
      }
      final expected = [0, 1, 2, 0, 1, 3, 0, 1, 4];
      expect(
        PerformancePlan(engine.composition.value).visits
            .map((v) => v.sourceIndex),
        expected,
      );
      final folder = await Directory.systemTemp.createTemp(
        'measure-mark-edits',
      );
      addTearDown(() => folder.delete(recursive: true));
      final storage = CompositionStorageService(
        documentsDirectory: () async => folder,
      );
      final saved = await storage.save(
        composition: engine.composition.value,
        rawEvents: engine.rawEvents,
      );
      final reopened = await storage.load(saved.path);
      expect(
        PerformancePlan(reopened.composition).visits.map((v) => v.sourceIndex),
        expected,
      );
      for (var i = 0; i < 5; i++) {
        final marks = MeasureMarks(reopened.composition.measures[i].barlines);
        if (i >= 2) {
          expect(marks.voltaNumber(MeasureEdge.left), '${i - 1}');
          expect(marks.voltaNumber(MeasureEdge.right), '${i - 1}');
        }
      }
    },
  );
}
