import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheet_music_rookie/app/app.dart';
import 'package:sheet_music_rookie/audio/microphone_service.dart';
import 'package:sheet_music_rookie/l10n/l10n.dart';
import 'package:sheet_music_rookie/l10n/generated/app_localizations_es.dart';
import 'package:sheet_music_rookie/models/app_language.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/pitch_detection_result.dart';
import 'package:sheet_music_rookie/models/voice_detection_settings.dart';
import 'package:sheet_music_rookie/notation/score_renderer.dart';
import 'package:sheet_music_rookie/services/settings_service.dart';
import 'package:sheet_music_rookie/widgets/live_pitch_monitor.dart';
import 'package:sheet_music_rookie/widgets/voice_settings_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> chooseLanguage(WidgetTester tester, String choice) async {
    await tester.tap(find.byType(DropdownButtonFormField<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Spanish device locale uses Partituras and keeps the app name', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('es', 'MX')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const SheetMusicRookieApp());
    await tester.pumpAndSettle();
    expect(find.text('Sheet Music Rookie'), findsOneWidget);
    expect(find.text('Partituras para Novatos'), findsOneWidget);
    expect(find.text('Partituras'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Elige una clave'), findsOneWidget);
    expect(find.text('Clave de Sol'), findsOneWidget);
    expect(find.text('Clave de Fa'), findsOneWidget);
  });

  testWidgets(
    'English override persists across restart and system restores automatic switching',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('es', 'ES')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const SheetMusicRookieApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ajustes'));
      await tester.tap(find.text('Ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('Idioma'), findsOneWidget);
      await chooseLanguage(tester, 'English');
      expect(find.text('Settings'), findsOneWidget);
      expect(await SettingsService().loadAppLanguage(), AppLanguage.english);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const SheetMusicRookieApp());
      await tester.pumpAndSettle();
      expect(find.text('Sheets'), findsOneWidget);
      expect(find.text('Partituras'), findsNothing);
      await tester.ensureVisible(find.text('Settings'));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await chooseLanguage(tester, 'Device language');
      expect(find.text('Ajustes'), findsOneWidget);
      expect(await SettingsService().loadAppLanguage(), AppLanguage.system);
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'GB')];
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    },
  );

  testWidgets(
    'unsupported device language falls back to English; Spanish can be chosen manually',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const SheetMusicRookieApp());
      await tester.pumpAndSettle();
      expect(find.text('Sheets'), findsOneWidget);
      await tester.ensureVisible(find.text('Settings'));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await chooseLanguage(tester, 'Español');
      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Sonido y práctica'), findsOneWidget);
      expect(await SettingsService().loadAppLanguage(), AppLanguage.spanish);
    },
  );

  test(
    'language preferences are independent of voice reset and invalid values',
    () async {
      SharedPreferences.setMockInitialValues({'app.language': 'fr'});
      final service = SettingsService();
      expect(await service.loadAppLanguage(), AppLanguage.system);
      await service.saveAppLanguage(AppLanguage.spanish);
      await service.save(const VoiceDetectionSettings());
      expect(await SettingsService().loadAppLanguage(), AppLanguage.spanish);
    },
  );

  test(
    'English and Spanish catalogs contain the same complete message set',
    () async {
      final english = jsonDecode(
        await File('lib/l10n/app_en.arb').readAsString(),
      ) as Map<String, dynamic>;
      final spanish = jsonDecode(
        await File('lib/l10n/app_es.arb').readAsString(),
      ) as Map<String, dynamic>;
      final keys = english.keys.where((key) => !key.startsWith('@')).toSet();
      expect(spanish.keys.where((key) => !key.startsWith('@')).toSet(), keys);
      for (final key in keys) {
        expect(spanish[key], isNotEmpty, reason: key);
      }
      final strings = AppLocalizationsEs();
      expect(strings.sheets, 'Partituras');
      expect(strings.measureCount(1), '1 compás');
      expect(strings.measureCount(3), '3 compases');
      expect(
        strings.sheetTitle('Untitled Composition'),
        'Partitura sin título',
      );
      expect(strings.sheetTitle('My canción “Sol”'), 'My canción “Sol”');
      expect(strings.keyLabel(KeySignature.gMajor), 'Sol mayor ♯');
      expect(strings.noteName('C♯'), 'Do♯');
    },
  );

  testWidgets('Spanish home fits a small screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.localesTestValue = [const Locale('es')];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const SheetMusicRookieApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ajustes'));
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Idioma'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Spanish voice controls, feedback, and score painter localize without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 350,
                    child: ScoreView(
                      composition: const Composition(clef: ClefType.treble),
                      scrollController: scroll,
                    ),
                  ),
                  LivePitchMonitor(
                    status: ValueNotifier(MicrophoneStatus.voiceDetected),
                    pitch: ValueNotifier<PitchDetectionResult?>(null),
                    durationMs: ValueNotifier(0),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: VoiceSettingsPanel(
                      value: const VoiceDetectionSettings(),
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('MICRÓFONO: VOZ DETECTADA'), findsOneWidget);
      final paint = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is ScorePainter,
        ),
      );
      expect((paint.painter as ScorePainter).strings!.localeName, 'es');
      await tester.ensureVisible(
        find.text('Restablecer valores predeterminados'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
