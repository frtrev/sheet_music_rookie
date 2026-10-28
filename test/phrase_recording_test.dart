import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/audio/phrase_analyzer.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/raw_note_event.dart';
import 'package:sheet_music_rookie/transcription/measure_builder.dart';
import 'package:sheet_music_rookie/models/phrase_draft.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';
import 'package:sheet_music_rookie/services/settings_service.dart';
import 'package:sheet_music_rookie/transcription/transcription_engine.dart';
import 'package:sheet_music_rookie/widgets/phrase_review_panel.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';

List<AudioFrame> tone(
  int start,
  int duration,
  double hz, {
  double amplitude = .3,
}) => [
  for (var time = start; time < start + duration; time += 25)
    AudioFrame(
      Float64List.fromList(
        List.generate(
          2048,
          (i) => amplitude * math.sin(2 * math.pi * hz * i / 44100),
        ),
      ),
      time,
    ),
];
List<AudioFrame> silence(int start, int duration) => [
  for (var time = start; time < start + duration; time += 25)
    AudioFrame(Float64List(2048), time),
];

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const settings = VoiceDetectionSettings(
    recordingAnalysisMode: RecordingAnalysisMode.phrase,
  );

  test('whole phrase preserves onset timing and ignores delimiter silence', () {
    final notes = analyzePhrase(
      PhraseAnalysisRequest(
        [
          ...tone(0, 500, 440),
          ...tone(500, 500, 493.88),
          ...silence(1000, 1200),
        ],
        settings,
        120,
      ),
    );
    expect(notes.map((n) => n.midiPitch), [69, 71]);
    expect(notes.map((n) => n.durationMs), [500, 500]);
  });

  test('long sustained notes are represented without truncating duration', () {
    final notes = analyzePhrase(
      PhraseAnalysisRequest(
        [...tone(0, 3000, 440), ...silence(3000, 1200)],
        settings,
        120,
      ),
    );
    expect(notes.fold<int>(0, (sum, n) => sum + n.durationMs), 3000);
    expect(notes.first.tieToNext, isTrue);
    expect(notes.last.tieToNext, isFalse);
  });

  test('fresh attacks distinguish repeated piano pitches', () {
    final notes = analyzePhrase(
      PhraseAnalysisRequest(
        [
          ...tone(0, 350, 440),
          ...tone(350, 150, 440, amplitude: .08),
          ...tone(500, 500, 440),
          ...silence(1000, 1200),
        ],
        settings,
        120,
      ),
    );
    expect(notes.map((n) => n.midiPitch), [69, 69]);
    expect(notes.map((n) => n.durationMs), [500, 500]);
  });

  test(
    'phrase settings persist and legacy settings retain live mode',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      expect(
        (await service.load()).recordingAnalysisMode,
        RecordingAnalysisMode.live,
      );
      await service.save(settings.copyWith(phraseSilenceMs: 1400));
      final loaded = await service.load();
      expect(loaded.recordingAnalysisMode, RecordingAnalysisMode.phrase);
      expect(loaded.phraseSilenceMs, 1400);
    },
  );

  test('silence produces a review, rejection is clean, acceptance is one undo step', () async {
    SharedPreferences.setMockInitialValues({});
    final mic = _Microphone();
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: mic,
    );
    await engine.initialize();
    await engine.updateSettings(settings);
    await engine.startListening();
    for (final frame in tone(0, 500, 440)) {
      mic.controller.add(frame);
    }
    expect(engine.rawEvents, isEmpty);
    expect(engine.phraseDraft.value?.stage, PhraseStage.recording);
    expect(engine.phraseDraft.value?.trace, isNotEmpty);
    for (final frame in silence(500, 1200)) {
      mic.controller.add(frame);
    }
    await engine.finishPhrase();
    // The silence delimiter starts the isolate before finishPhrase is called.
    while (engine.phraseDraft.value?.stage == PhraseStage.analyzing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(engine.phraseDraft.value?.stage, PhraseStage.review);
    expect(engine.phraseDraft.value?.preview?.measures.first.notes, isNotEmpty);
    expect(engine.rawEvents, isEmpty);
    expect(engine.canUndo, isFalse);
    engine.discardPhrase();
    expect(engine.hasUnsavedChanges, isFalse);
    for (final frame in tone(2000, 500, 493.88)) {
      mic.controller.add(frame);
    }
    await engine.pauseListening();
    expect(engine.phraseDraft.value?.stage, PhraseStage.review);
    expect(engine.acceptPhrase(), isTrue);
    expect(engine.rawEvents.single.midiPitch, 71);
    expect(engine.undo(), isTrue);
    expect(engine.rawEvents, isEmpty);
    expect(engine.canUndo, isFalse);
    expect(engine.redo(), isTrue);
    expect(engine.rawEvents.single.midiPitch, 71);
    await engine.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Stop followed by No leaves an empty score unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    final mic = _Microphone();
    final engine = TranscriptionEngine(
      clef: ClefType.treble,
      octaveRange: OctaveRange.standard,
      microphone: mic,
    );
    await engine.initialize();
    await engine.updateSettings(settings);
    await engine.startListening();
    for (final frame in tone(0, 500, 440)) {
      mic.controller.add(frame);
    }
    await engine.pauseListening();
    engine.discardPhrase();
    expect(engine.hasUnsavedChanges, isFalse);
    expect(engine.rawEvents, isEmpty);
    expect(engine.canUndo, isFalse);
    await engine.dispose();
  });

  test(
    'accepted phrases overwrite only their span and preserve later notes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final original = [
        for (var i = 0; i < 3; i++)
          RawNoteEvent(
            startTimeMs: i * 500,
            endTimeMs: (i + 1) * 500,
            frequencyHz: 440,
            midiPitch: 60 + i * 2,
            confidence: 1,
          ),
      ];
      final mic = _Microphone();
      final engine = TranscriptionEngine(
        clef: ClefType.treble,
        octaveRange: OctaveRange.standard,
        microphone: mic,
        initialEvents: original,
        initialComposition: Composition(
          clef: ClefType.treble,
          measures: const MeasureBuilder().build(original, 120, 4),
        ),
      );
      await engine.initialize();
      await engine.updateSettings(settings);
      engine.beginPunchInAt(480);
      await engine.startListening();
      for (final frame in tone(0, 500, 440)) {
        mic.controller.add(frame);
      }
      await engine.pauseListening();
      expect(engine.rawEvents.map((n) => n.midiPitch), [60, 62, 64]);
      expect(engine.phraseDraft.value?.startTick, 480);
      expect(engine.acceptPhrase(), isTrue);
      expect(engine.rawEvents.map((n) => n.midiPitch), [60, 69, 64]);
      expect(engine.rawEvents.last.startTimeMs, 1000);
      engine.undo();
      expect(engine.rawEvents.map((n) => n.midiPitch), [60, 62, 64]);
      await engine.dispose();
    },
  );

  testWidgets('review shows grey score notes, trace and explicit Yes and No', (
    tester,
  ) async {
    final notes = analyzePhrase(
      PhraseAnalysisRequest([...tone(0, 500, 440)], settings, 120),
    );
    final draft = PhraseDraft(
      stage: PhraseStage.review,
      startTick: 0,
      events: notes,
    );
    var accepted = false;
    var rejected = false;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final screenshotKey = GlobalKey();
    final preview = Composition(
      clef: ClefType.treble,
      measures: const MeasureBuilder().build(notes, 120, 4),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: ScoreView(
                    composition: preview,
                    scrollController: controller,
                    previewStartTick: 0,
                    previewEndTick: 480,
                    pitchTrace: const [
                      PitchTracePoint(0, 69),
                      PitchTracePoint(480, 71),
                    ],
                  ),
                ),
                PhraseReviewPanel(
                  draft: draft,
                  onAccept: () => accepted = true,
                  onDiscard: () => rejected = true,
                  onFinish: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.tap(find.text('No'));
    expect(accepted, isTrue);
    expect(rejected, isTrue);
    expect(tester.takeException(), isNull);
    final screenshot = Platform.environment['PHRASE_SCREENSHOT'];
    if (screenshot != null) {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshot).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
