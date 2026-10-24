import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/app/app.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';
import 'package:sheet_music_rookie/widgets/voice_settings_panel.dart';

void main() {
  testWidgets('home offers the three main menu choices', (tester) async {
    await tester.pumpWidget(const SheetMusicRookieApp());

    expect(find.text('Sheet Music Rookie'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Treble Clef'), findsOneWidget);
    expect(find.text('Bass Clef'), findsOneWidget);

    await tester.tap(find.text('Treble Clef'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an octave range'), findsOneWidget);
    expect(find.text('8 down'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('8 up'), findsOneWidget);
  });

  testWidgets('settings begin with the three practice controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceSettingsPanel(
              value: const VoiceDetectionSettings(),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final difficulty = find.text('Practice difficulty');
    final stability = find.text('Pitch stability');
    final tolerance = find.text('Pitch tolerance (capture & practice)');
    final minimumFrequency = find.text('Minimum frequency');
    expect(difficulty, findsOneWidget);
    expect(stability, findsOneWidget);
    expect(tolerance, findsOneWidget);
    expect(find.textContaining('Optimize for'), findsNothing);
    expect(
      tester.getTopLeft(difficulty).dy,
      lessThan(tester.getTopLeft(stability).dy),
    );
    expect(
      tester.getTopLeft(stability).dy,
      lessThan(tester.getTopLeft(tolerance).dy),
    );
    expect(
      tester.getTopLeft(tolerance).dy,
      lessThan(tester.getTopLeft(minimumFrequency).dy),
    );
  });
}
