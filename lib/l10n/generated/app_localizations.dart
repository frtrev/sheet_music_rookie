import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @singItSeeItShapeIt.
  ///
  /// In en, this message translates to:
  /// **'Sing it. See it. Shape it.'**
  String get singItSeeItShapeIt;

  /// No description provided for @yourVoiceYourMusic.
  ///
  /// In en, this message translates to:
  /// **'Your voice. Your music.'**
  String get yourVoiceYourMusic;

  /// No description provided for @turnAMelodyIntoSheetMusicOneNoteAtATime.
  ///
  /// In en, this message translates to:
  /// **'Turn a melody into sheet music, one note at a time.'**
  String get turnAMelodyIntoSheetMusicOneNoteAtATime;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @sheets.
  ///
  /// In en, this message translates to:
  /// **'Sheets'**
  String get sheets;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @offlineNoAccountRequired.
  ///
  /// In en, this message translates to:
  /// **'Offline • No account required'**
  String get offlineNoAccountRequired;

  /// No description provided for @chooseAClef.
  ///
  /// In en, this message translates to:
  /// **'Choose a clef'**
  String get chooseAClef;

  /// No description provided for @savedSheetsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Saved sheets could not be read.'**
  String get savedSheetsCouldNotBeRead;

  /// No description provided for @theSheetCouldNotBeShared.
  ///
  /// In en, this message translates to:
  /// **'The sheet could not be shared.'**
  String get theSheetCouldNotBeShared;

  /// No description provided for @chooseAnOctaveRange.
  ///
  /// In en, this message translates to:
  /// **'Choose an octave range'**
  String get chooseAnOctaveRange;

  /// No description provided for @detectedNotesWillBeWrittenAndPlayedInThisRange.
  ///
  /// In en, this message translates to:
  /// **'Detected notes will be written and played in this range.'**
  String get detectedNotesWillBeWrittenAndPlayedInThisRange;

  /// No description provided for @writeTwoOctavesBelowTheDetectedPitch.
  ///
  /// In en, this message translates to:
  /// **'Write two octaves below the detected pitch'**
  String get writeTwoOctavesBelowTheDetectedPitch;

  /// No description provided for @writeOneOctaveBelowTheDetectedPitch.
  ///
  /// In en, this message translates to:
  /// **'Write one octave below the detected pitch'**
  String get writeOneOctaveBelowTheDetectedPitch;

  /// No description provided for @writeAtTheDetectedPitch.
  ///
  /// In en, this message translates to:
  /// **'Write at the detected pitch'**
  String get writeAtTheDetectedPitch;

  /// No description provided for @writeOneOctaveAboveTheDetectedPitch.
  ///
  /// In en, this message translates to:
  /// **'Write one octave above the detected pitch'**
  String get writeOneOctaveAboveTheDetectedPitch;

  /// No description provided for @writeTwoOctavesAboveTheDetectedPitch.
  ///
  /// In en, this message translates to:
  /// **'Write two octaves above the detected pitch'**
  String get writeTwoOctavesAboveTheDetectedPitch;

  /// No description provided for @saveImportedScore.
  ///
  /// In en, this message translates to:
  /// **'Save imported score?'**
  String get saveImportedScore;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @thisImportedScoreHasNotBeenSavedToYourLibrarySaveItBeforeLeaving.
  ///
  /// In en, this message translates to:
  /// **'This imported score has not been saved to your library. Save it before leaving?'**
  String get thisImportedScoreHasNotBeenSavedToYourLibrarySaveItBeforeLeaving;

  /// No description provided for @yourScoreHasUnsavedChangesSaveThemBeforeLeaving.
  ///
  /// In en, this message translates to:
  /// **'Your score has unsaved changes. Save them before leaving?'**
  String get yourScoreHasUnsavedChangesSaveThemBeforeLeaving;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @saveLeave.
  ///
  /// In en, this message translates to:
  /// **'Save & leave'**
  String get saveLeave;

  /// No description provided for @clearTheSheet.
  ///
  /// In en, this message translates to:
  /// **'Clear the sheet?'**
  String get clearTheSheet;

  /// No description provided for @allTranscribedNotesInThisCompositionWillBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'All transcribed notes in this composition will be removed.'**
  String get allTranscribedNotesInThisCompositionWillBeRemoved;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @saveComposition.
  ///
  /// In en, this message translates to:
  /// **'Save composition'**
  String get saveComposition;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @myComposition.
  ///
  /// In en, this message translates to:
  /// **'My composition'**
  String get myComposition;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @theCompositionCouldNotBeSaved.
  ///
  /// In en, this message translates to:
  /// **'The composition could not be saved.'**
  String get theCompositionCouldNotBeSaved;

  /// No description provided for @singAFewNotesBeforePlayingTheScore.
  ///
  /// In en, this message translates to:
  /// **'Sing a few notes before playing the score.'**
  String get singAFewNotesBeforePlayingTheScore;

  /// No description provided for @addSomeNotesBeforePracticing.
  ///
  /// In en, this message translates to:
  /// **'Add some notes before practicing.'**
  String get addSomeNotesBeforePracticing;

  /// No description provided for @practiceComplete.
  ///
  /// In en, this message translates to:
  /// **'Practice complete!'**
  String get practiceComplete;

  /// No description provided for @addSomeNotesBeforeStartingATest.
  ///
  /// In en, this message translates to:
  /// **'Add some notes before starting a test.'**
  String get addSomeNotesBeforeStartingATest;

  /// No description provided for @melodyTestResult.
  ///
  /// In en, this message translates to:
  /// **'Melody test result'**
  String get melodyTestResult;

  /// No description provided for @outOf100.
  ///
  /// In en, this message translates to:
  /// **'out of 100'**
  String get outOf100;

  /// No description provided for @pitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get pitch;

  /// No description provided for @timing.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get timing;

  /// No description provided for @listenToMatch.
  ///
  /// In en, this message translates to:
  /// **'Listen to match'**
  String get listenToMatch;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @acceptOrDiscardTheRecordingPhraseBelowTheScoreFirst.
  ///
  /// In en, this message translates to:
  /// **'Accept or discard the recording phrase below the score first.'**
  String get acceptOrDiscardTheRecordingPhraseBelowTheScoreFirst;

  /// No description provided for @tempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get tempo;

  /// No description provided for @beatsPerMinute.
  ///
  /// In en, this message translates to:
  /// **'Beats per minute'**
  String get beatsPerMinute;

  /// No description provided for @message20400Bpm.
  ///
  /// In en, this message translates to:
  /// **'20–400 BPM'**
  String get message20400Bpm;

  /// No description provided for @enterAWholeNumberFrom20To400.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 20 to 400.'**
  String get enterAWholeNumberFrom20To400;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @playbackInstrument.
  ///
  /// In en, this message translates to:
  /// **'Playback instrument'**
  String get playbackInstrument;

  /// No description provided for @generaluserGsSampledInstrumentsOffline.
  ///
  /// In en, this message translates to:
  /// **'GeneralUser GS · sampled instruments · offline'**
  String get generaluserGsSampledInstrumentsOffline;

  /// No description provided for @soundLibraryLicenses.
  ///
  /// In en, this message translates to:
  /// **'Sound library licenses'**
  String get soundLibraryLicenses;

  /// No description provided for @chooseAMajorKey.
  ///
  /// In en, this message translates to:
  /// **'Choose a major key'**
  String get chooseAMajorKey;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @chooseOctaveRange.
  ///
  /// In en, this message translates to:
  /// **'Choose octave range'**
  String get chooseOctaveRange;

  /// No description provided for @writtenAndSoundingPitchMatch.
  ///
  /// In en, this message translates to:
  /// **'Written and sounding pitch match'**
  String get writtenAndSoundingPitchMatch;

  /// No description provided for @beats.
  ///
  /// In en, this message translates to:
  /// **'Beats'**
  String get beats;

  /// No description provided for @noteValue.
  ///
  /// In en, this message translates to:
  /// **'Note value'**
  String get noteValue;

  /// No description provided for @audioVolumes.
  ///
  /// In en, this message translates to:
  /// **'Audio volumes'**
  String get audioVolumes;

  /// No description provided for @theMetronomeCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'The metronome could not start.'**
  String get theMetronomeCouldNotStart;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @saveComposition2.
  ///
  /// In en, this message translates to:
  /// **'Save Composition'**
  String get saveComposition2;

  /// No description provided for @clearSheet.
  ///
  /// In en, this message translates to:
  /// **'Clear Sheet'**
  String get clearSheet;

  /// No description provided for @tapAnywhereOnTheStaffToPlaceTheCursorRecordingStaysActiveAndContinuesOverwritingFromTheSelectedNote.
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere on the staff to place the cursor. Recording stays active and continues overwriting from the selected note.'**
  String
  get tapAnywhereOnTheStaffToPlaceTheCursorRecordingStaysActiveAndContinuesOverwritingFromTheSelectedNote;

  /// No description provided for @microphoneUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone unavailable'**
  String get microphoneUnavailable;

  /// No description provided for @allowMicrophoneAccessInSystemSettingsThenTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Allow microphone access in system settings, then try again.'**
  String get allowMicrophoneAccessInSystemSettingsThenTryAgain;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @recognitionPracticeAndTestPlayback.
  ///
  /// In en, this message translates to:
  /// **'Recognition, practice, and test playback'**
  String get recognitionPracticeAndTestPlayback;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @stopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get stopRecording;

  /// No description provided for @startRecording.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get startRecording;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @stopPlayback.
  ///
  /// In en, this message translates to:
  /// **'Stop playback'**
  String get stopPlayback;

  /// No description provided for @playScore.
  ///
  /// In en, this message translates to:
  /// **'Play score'**
  String get playScore;

  /// No description provided for @practice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get practice;

  /// No description provided for @stopPractice.
  ///
  /// In en, this message translates to:
  /// **'Stop practice'**
  String get stopPractice;

  /// No description provided for @startPractice.
  ///
  /// In en, this message translates to:
  /// **'Start practice'**
  String get startPractice;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @stopMelodyTest.
  ///
  /// In en, this message translates to:
  /// **'Stop melody test'**
  String get stopMelodyTest;

  /// No description provided for @startMelodyTest.
  ///
  /// In en, this message translates to:
  /// **'Start melody test'**
  String get startMelodyTest;

  /// No description provided for @playSelectedNote.
  ///
  /// In en, this message translates to:
  /// **'Play selected note'**
  String get playSelectedNote;

  /// No description provided for @changeToFirstLineNote.
  ///
  /// In en, this message translates to:
  /// **'Change to first-line note'**
  String get changeToFirstLineNote;

  /// No description provided for @addOneBeatNoteAtNearestBeat.
  ///
  /// In en, this message translates to:
  /// **'Add one-beat note at nearest beat'**
  String get addOneBeatNoteAtNearestBeat;

  /// No description provided for @changeToRest.
  ///
  /// In en, this message translates to:
  /// **'Change to rest'**
  String get changeToRest;

  /// No description provided for @addOneBeatRestAtNearestBeat.
  ///
  /// In en, this message translates to:
  /// **'Add one-beat rest at nearest beat'**
  String get addOneBeatRestAtNearestBeat;

  /// No description provided for @nextLyricLine.
  ///
  /// In en, this message translates to:
  /// **'Next lyric line'**
  String get nextLyricLine;

  /// No description provided for @downOneSemitone.
  ///
  /// In en, this message translates to:
  /// **'Down one semitone'**
  String get downOneSemitone;

  /// No description provided for @previousLyricLine.
  ///
  /// In en, this message translates to:
  /// **'Previous lyric line'**
  String get previousLyricLine;

  /// No description provided for @upOneSemitone.
  ///
  /// In en, this message translates to:
  /// **'Up one semitone'**
  String get upOneSemitone;

  /// No description provided for @shorterNote.
  ///
  /// In en, this message translates to:
  /// **'Shorter note'**
  String get shorterNote;

  /// No description provided for @longerNote.
  ///
  /// In en, this message translates to:
  /// **'Longer note'**
  String get longerNote;

  /// No description provided for @editLyrics.
  ///
  /// In en, this message translates to:
  /// **'Edit lyrics'**
  String get editLyrics;

  /// No description provided for @muteTappedNotes.
  ///
  /// In en, this message translates to:
  /// **'Mute tapped notes'**
  String get muteTappedNotes;

  /// No description provided for @playTappedNotes.
  ///
  /// In en, this message translates to:
  /// **'Play tapped notes'**
  String get playTappedNotes;

  /// No description provided for @removeTie.
  ///
  /// In en, this message translates to:
  /// **'Remove tie'**
  String get removeTie;

  /// No description provided for @tieToNextNote.
  ///
  /// In en, this message translates to:
  /// **'Tie to next note'**
  String get tieToNextNote;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @insertBlankMeasureAfterCurrentMeasure.
  ///
  /// In en, this message translates to:
  /// **'Insert blank measure after current measure'**
  String get insertBlankMeasureAfterCurrentMeasure;

  /// No description provided for @removeSelectedNoteOrRest.
  ///
  /// In en, this message translates to:
  /// **'Remove selected note or rest'**
  String get removeSelectedNoteOrRest;

  /// No description provided for @volumes.
  ///
  /// In en, this message translates to:
  /// **'Volumes'**
  String get volumes;

  /// No description provided for @soundPractice.
  ///
  /// In en, this message translates to:
  /// **'Sound & practice'**
  String get soundPractice;

  /// No description provided for @personalizeVoicePolishPracticeAndRecognitionEverythingRunsOffline.
  ///
  /// In en, this message translates to:
  /// **'Personalize voice polish, practice, and recognition. Everything runs offline.'**
  String get personalizeVoicePolishPracticeAndRecognitionEverythingRunsOffline;

  /// No description provided for @practiceDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Practice difficulty'**
  String get practiceDifficulty;

  /// No description provided for @pitchStability.
  ///
  /// In en, this message translates to:
  /// **'Pitch stability'**
  String get pitchStability;

  /// No description provided for @pitchToleranceCapturePractice.
  ///
  /// In en, this message translates to:
  /// **'Pitch tolerance (capture & practice)'**
  String get pitchToleranceCapturePractice;

  /// No description provided for @recordingAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Recording analysis'**
  String get recordingAnalysis;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @reviewAfterAPhrase.
  ///
  /// In en, this message translates to:
  /// **'Review after a phrase'**
  String get reviewAfterAPhrase;

  /// No description provided for @phraseModeWaitsForSilenceThenShowsAPitchTraceAndPreviewNotesOnlyAcceptedPhrasesAreWrittenToTheScorePlayOrSingOneNoteAtATime.
  ///
  /// In en, this message translates to:
  /// **'Phrase mode waits for silence, then shows a pitch trace and preview notes. Only accepted phrases are written to the score. Play or sing one note at a time.'**
  String
  get phraseModeWaitsForSilenceThenShowsAPitchTraceAndPreviewNotesOnlyAcceptedPhrasesAreWrittenToTheScorePlayOrSingOneNoteAtATime;

  /// No description provided for @phraseSilence.
  ///
  /// In en, this message translates to:
  /// **'Phrase silence'**
  String get phraseSilence;

  /// No description provided for @automaticCursorPosition.
  ///
  /// In en, this message translates to:
  /// **'Automatic cursor position'**
  String get automaticCursorPosition;

  /// No description provided for @voicePolishTestPlayback.
  ///
  /// In en, this message translates to:
  /// **'Voice polish (test playback)'**
  String get voicePolishTestPlayback;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @aClearerSmootherVoiceWithSubtleRoomAmbienceAppliesToYourNextTestPlaybackPitchAndScoringStayUnchanged.
  ///
  /// In en, this message translates to:
  /// **'A clearer, smoother voice with subtle room ambience. Applies to your next test playback; pitch and scoring stay unchanged.'**
  String
  get aClearerSmootherVoiceWithSubtleRoomAmbienceAppliesToYourNextTestPlaybackPitchAndScoringStayUnchanged;

  /// No description provided for @minimumFrequency.
  ///
  /// In en, this message translates to:
  /// **'Minimum frequency'**
  String get minimumFrequency;

  /// No description provided for @maximumFrequency.
  ///
  /// In en, this message translates to:
  /// **'Maximum frequency'**
  String get maximumFrequency;

  /// No description provided for @minimumConfidence.
  ///
  /// In en, this message translates to:
  /// **'Minimum confidence'**
  String get minimumConfidence;

  /// No description provided for @minimumNoteDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum note duration'**
  String get minimumNoteDuration;

  /// No description provided for @silenceThreshold.
  ///
  /// In en, this message translates to:
  /// **'Silence threshold'**
  String get silenceThreshold;

  /// No description provided for @silenceDuration.
  ///
  /// In en, this message translates to:
  /// **'Silence duration'**
  String get silenceDuration;

  /// No description provided for @repeatedSyllableGap.
  ///
  /// In en, this message translates to:
  /// **'Repeated-syllable gap'**
  String get repeatedSyllableGap;

  /// No description provided for @smoothingWindow.
  ///
  /// In en, this message translates to:
  /// **'Smoothing window'**
  String get smoothingWindow;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// No description provided for @playbackCouldNotBeStopped.
  ///
  /// In en, this message translates to:
  /// **'Playback could not be stopped.'**
  String get playbackCouldNotBeStopped;

  /// No description provided for @thisSheetHasNoPlayableNotes.
  ///
  /// In en, this message translates to:
  /// **'This sheet has no playable notes.'**
  String get thisSheetHasNoPlayableNotes;

  /// No description provided for @theSheetCouldNotBePlayed.
  ///
  /// In en, this message translates to:
  /// **'The sheet could not be played.'**
  String get theSheetCouldNotBePlayed;

  /// No description provided for @removeSheet.
  ///
  /// In en, this message translates to:
  /// **'Remove {title}'**
  String removeSheet(String title);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @theSheetCouldNotBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'The sheet could not be removed.'**
  String get theSheetCouldNotBeRemoved;

  /// No description provided for @noSavedSheetsYet.
  ///
  /// In en, this message translates to:
  /// **'No saved sheets yet.'**
  String get noSavedSheetsYet;

  /// No description provided for @finishLyricEditing.
  ///
  /// In en, this message translates to:
  /// **'Finish lyric editing'**
  String get finishLyricEditing;

  /// No description provided for @detectedNote.
  ///
  /// In en, this message translates to:
  /// **'Detected note'**
  String get detectedNote;

  /// No description provided for @frequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequency;

  /// No description provided for @confidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get confidence;

  /// No description provided for @pitchOffset.
  ///
  /// In en, this message translates to:
  /// **'Pitch offset'**
  String get pitchOffset;

  /// No description provided for @amplitude.
  ///
  /// In en, this message translates to:
  /// **'Amplitude'**
  String get amplitude;

  /// No description provided for @currentDuration.
  ///
  /// In en, this message translates to:
  /// **'Current duration'**
  String get currentDuration;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'STARTING'**
  String get starting;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'LISTENING'**
  String get listening;

  /// No description provided for @voiceDetected.
  ///
  /// In en, this message translates to:
  /// **'VOICE DETECTED'**
  String get voiceDetected;

  /// No description provided for @silence.
  ///
  /// In en, this message translates to:
  /// **'SILENCE'**
  String get silence;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get paused;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'UNAVAILABLE'**
  String get unavailable;

  /// No description provided for @pitchGaugeInactive.
  ///
  /// In en, this message translates to:
  /// **'Pitch gauge inactive'**
  String get pitchGaugeInactive;

  /// No description provided for @pitchGaugeWaitingForATone.
  ///
  /// In en, this message translates to:
  /// **'Pitch gauge waiting for a tone'**
  String get pitchGaugeWaitingForATone;

  /// No description provided for @listeningToYourPhrase.
  ///
  /// In en, this message translates to:
  /// **'Listening to your phrase…'**
  String get listeningToYourPhrase;

  /// No description provided for @analyzingYourPhrase.
  ///
  /// In en, this message translates to:
  /// **'Analyzing your phrase…'**
  String get analyzingYourPhrase;

  /// No description provided for @writeThisPhraseToTheScore.
  ///
  /// In en, this message translates to:
  /// **'Write this phrase to the score?'**
  String get writeThisPhraseToTheScore;

  /// No description provided for @noClearNotesFound.
  ///
  /// In en, this message translates to:
  /// **'No clear notes found.'**
  String get noClearNotesFound;

  /// No description provided for @noClearNotesFoundTryAgainOrAdjustTheDetectionSettings.
  ///
  /// In en, this message translates to:
  /// **'No clear notes found. Try again or adjust the detection settings.'**
  String get noClearNotesFoundTryAgainOrAdjustTheDetectionSettings;

  /// No description provided for @couldNotAnalyzeThisPhraseDiscardItAndTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not analyze this phrase. Discard it and try again.'**
  String get couldNotAnalyzeThisPhraseDiscardItAndTryAgain;

  /// No description provided for @pauseToReviewOrTapReviewNowUpTo30SecondsPerPhrase.
  ///
  /// In en, this message translates to:
  /// **'Pause to review, or tap Review now. Up to 30 seconds per phrase.'**
  String get pauseToReviewOrTapReviewNowUpTo30SecondsPerPhrase;

  /// No description provided for @greyNotesAreAPreviewRecordingWaitsForYourChoice.
  ///
  /// In en, this message translates to:
  /// **'Grey notes are a preview. Recording waits for your choice.'**
  String get greyNotesAreAPreviewRecordingWaitsForYourChoice;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @reviewNow.
  ///
  /// In en, this message translates to:
  /// **'Review now'**
  String get reviewNow;

  /// No description provided for @thisScoreFileCouldNotBeOpened.
  ///
  /// In en, this message translates to:
  /// **'This score file could not be opened.'**
  String get thisScoreFileCouldNotBeOpened;

  /// No description provided for @untitledComposition.
  ///
  /// In en, this message translates to:
  /// **'Untitled Composition'**
  String get untitledComposition;

  /// No description provided for @treble.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get treble;

  /// No description provided for @bass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get bass;

  /// No description provided for @alto.
  ///
  /// In en, this message translates to:
  /// **'Alto'**
  String get alto;

  /// No description provided for @tenor.
  ///
  /// In en, this message translates to:
  /// **'Tenor'**
  String get tenor;

  /// No description provided for @message15Down.
  ///
  /// In en, this message translates to:
  /// **'15 down'**
  String get message15Down;

  /// No description provided for @message8Down.
  ///
  /// In en, this message translates to:
  /// **'8 down'**
  String get message8Down;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @message8Up.
  ///
  /// In en, this message translates to:
  /// **'8 up'**
  String get message8Up;

  /// No description provided for @message15Up.
  ///
  /// In en, this message translates to:
  /// **'15 up'**
  String get message15Up;

  /// No description provided for @metronomeOff.
  ///
  /// In en, this message translates to:
  /// **'Metronome off'**
  String get metronomeOff;

  /// No description provided for @metronomeOn.
  ///
  /// In en, this message translates to:
  /// **'Metronome on'**
  String get metronomeOn;

  /// No description provided for @metronomeSingle.
  ///
  /// In en, this message translates to:
  /// **'Metronome single'**
  String get metronomeSingle;

  /// No description provided for @beginner.
  ///
  /// In en, this message translates to:
  /// **'Beginner'**
  String get beginner;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @keepsEarnedProgressWhenThePitchIsMissed.
  ///
  /// In en, this message translates to:
  /// **'Keeps earned progress when the pitch is missed.'**
  String get keepsEarnedProgressWhenThePitchIsMissed;

  /// No description provided for @resetsProgressForTheCurrentNote.
  ///
  /// In en, this message translates to:
  /// **'Resets progress for the current note.'**
  String get resetsProgressForTheCurrentNote;

  /// No description provided for @returnsToTheBeginningOfTheScore.
  ///
  /// In en, this message translates to:
  /// **'Returns to the beginning of the score.'**
  String get returnsToTheBeginningOfTheScore;

  /// No description provided for @keyboards.
  ///
  /// In en, this message translates to:
  /// **'Keyboards'**
  String get keyboards;

  /// No description provided for @strings.
  ///
  /// In en, this message translates to:
  /// **'Strings'**
  String get strings;

  /// No description provided for @winds.
  ///
  /// In en, this message translates to:
  /// **'Winds'**
  String get winds;

  /// No description provided for @piano.
  ///
  /// In en, this message translates to:
  /// **'Piano'**
  String get piano;

  /// No description provided for @brightPiano.
  ///
  /// In en, this message translates to:
  /// **'Bright piano'**
  String get brightPiano;

  /// No description provided for @electricPiano.
  ///
  /// In en, this message translates to:
  /// **'Electric piano'**
  String get electricPiano;

  /// No description provided for @harpsichord.
  ///
  /// In en, this message translates to:
  /// **'Harpsichord'**
  String get harpsichord;

  /// No description provided for @drawbarOrgan.
  ///
  /// In en, this message translates to:
  /// **'Drawbar organ'**
  String get drawbarOrgan;

  /// No description provided for @churchOrgan.
  ///
  /// In en, this message translates to:
  /// **'Church organ'**
  String get churchOrgan;

  /// No description provided for @reedOrgan.
  ///
  /// In en, this message translates to:
  /// **'Reed organ'**
  String get reedOrgan;

  /// No description provided for @accordion.
  ///
  /// In en, this message translates to:
  /// **'Accordion'**
  String get accordion;

  /// No description provided for @harmonica.
  ///
  /// In en, this message translates to:
  /// **'Harmonica'**
  String get harmonica;

  /// No description provided for @nylonGuitar.
  ///
  /// In en, this message translates to:
  /// **'Nylon guitar'**
  String get nylonGuitar;

  /// No description provided for @steelStringGuitar.
  ///
  /// In en, this message translates to:
  /// **'Steel-string guitar'**
  String get steelStringGuitar;

  /// No description provided for @acousticBass.
  ///
  /// In en, this message translates to:
  /// **'Acoustic bass'**
  String get acousticBass;

  /// No description provided for @violin.
  ///
  /// In en, this message translates to:
  /// **'Violin'**
  String get violin;

  /// No description provided for @viola.
  ///
  /// In en, this message translates to:
  /// **'Viola'**
  String get viola;

  /// No description provided for @cello.
  ///
  /// In en, this message translates to:
  /// **'Cello'**
  String get cello;

  /// No description provided for @contrabass.
  ///
  /// In en, this message translates to:
  /// **'Contrabass'**
  String get contrabass;

  /// No description provided for @pizzicatoStrings.
  ///
  /// In en, this message translates to:
  /// **'Pizzicato strings'**
  String get pizzicatoStrings;

  /// No description provided for @harp.
  ///
  /// In en, this message translates to:
  /// **'Harp'**
  String get harp;

  /// No description provided for @stringEnsemble.
  ///
  /// In en, this message translates to:
  /// **'String ensemble'**
  String get stringEnsemble;

  /// No description provided for @trumpet.
  ///
  /// In en, this message translates to:
  /// **'Trumpet'**
  String get trumpet;

  /// No description provided for @trombone.
  ///
  /// In en, this message translates to:
  /// **'Trombone'**
  String get trombone;

  /// No description provided for @tuba.
  ///
  /// In en, this message translates to:
  /// **'Tuba'**
  String get tuba;

  /// No description provided for @frenchHorn.
  ///
  /// In en, this message translates to:
  /// **'French horn'**
  String get frenchHorn;

  /// No description provided for @sopranoSaxophone.
  ///
  /// In en, this message translates to:
  /// **'Soprano saxophone'**
  String get sopranoSaxophone;

  /// No description provided for @altoSaxophone.
  ///
  /// In en, this message translates to:
  /// **'Alto saxophone'**
  String get altoSaxophone;

  /// No description provided for @tenorSaxophone.
  ///
  /// In en, this message translates to:
  /// **'Tenor saxophone'**
  String get tenorSaxophone;

  /// No description provided for @baritoneSaxophone.
  ///
  /// In en, this message translates to:
  /// **'Baritone saxophone'**
  String get baritoneSaxophone;

  /// No description provided for @oboe.
  ///
  /// In en, this message translates to:
  /// **'Oboe'**
  String get oboe;

  /// No description provided for @englishHorn.
  ///
  /// In en, this message translates to:
  /// **'English horn'**
  String get englishHorn;

  /// No description provided for @bassoon.
  ///
  /// In en, this message translates to:
  /// **'Bassoon'**
  String get bassoon;

  /// No description provided for @clarinet.
  ///
  /// In en, this message translates to:
  /// **'Clarinet'**
  String get clarinet;

  /// No description provided for @piccolo.
  ///
  /// In en, this message translates to:
  /// **'Piccolo'**
  String get piccolo;

  /// No description provided for @flute.
  ///
  /// In en, this message translates to:
  /// **'Flute'**
  String get flute;

  /// No description provided for @recorder.
  ///
  /// In en, this message translates to:
  /// **'Recorder'**
  String get recorder;

  /// No description provided for @panFlute.
  ///
  /// In en, this message translates to:
  /// **'Pan flute'**
  String get panFlute;

  /// No description provided for @shakuhachi.
  ///
  /// In en, this message translates to:
  /// **'Shakuhachi'**
  String get shakuhachi;

  /// No description provided for @ocarina.
  ///
  /// In en, this message translates to:
  /// **'Ocarina'**
  String get ocarina;

  /// No description provided for @cMajor.
  ///
  /// In en, this message translates to:
  /// **'C Major'**
  String get cMajor;

  /// No description provided for @gMajor.
  ///
  /// In en, this message translates to:
  /// **'G Major'**
  String get gMajor;

  /// No description provided for @dMajor.
  ///
  /// In en, this message translates to:
  /// **'D Major'**
  String get dMajor;

  /// No description provided for @aMajor.
  ///
  /// In en, this message translates to:
  /// **'A Major'**
  String get aMajor;

  /// No description provided for @eMajor.
  ///
  /// In en, this message translates to:
  /// **'E Major'**
  String get eMajor;

  /// No description provided for @bMajor.
  ///
  /// In en, this message translates to:
  /// **'B Major'**
  String get bMajor;

  /// No description provided for @fMajor.
  ///
  /// In en, this message translates to:
  /// **'F♯ Major'**
  String get fMajor;

  /// No description provided for @cMajor2.
  ///
  /// In en, this message translates to:
  /// **'C♯ Major'**
  String get cMajor2;

  /// No description provided for @fMajor2.
  ///
  /// In en, this message translates to:
  /// **'F Major'**
  String get fMajor2;

  /// No description provided for @bMajor2.
  ///
  /// In en, this message translates to:
  /// **'B♭ Major'**
  String get bMajor2;

  /// No description provided for @eMajor2.
  ///
  /// In en, this message translates to:
  /// **'E♭ Major'**
  String get eMajor2;

  /// No description provided for @aMajor2.
  ///
  /// In en, this message translates to:
  /// **'A♭ Major'**
  String get aMajor2;

  /// No description provided for @dMajor2.
  ///
  /// In en, this message translates to:
  /// **'D♭ Major'**
  String get dMajor2;

  /// No description provided for @gMajor2.
  ///
  /// In en, this message translates to:
  /// **'G♭ Major'**
  String get gMajor2;

  /// No description provided for @cMajor3.
  ///
  /// In en, this message translates to:
  /// **'C♭ Major'**
  String get cMajor3;

  /// No description provided for @savedLocally.
  ///
  /// In en, this message translates to:
  /// **'Saved “{title}” locally as compressed MusicXML.'**
  String savedLocally(String title);

  /// No description provided for @removeSheetNamed.
  ///
  /// In en, this message translates to:
  /// **'Remove “{title}” from your saved sheets?'**
  String removeSheetNamed(String title);

  /// No description provided for @playSheet.
  ///
  /// In en, this message translates to:
  /// **'Play {title}'**
  String playSheet(String title);

  /// No description provided for @stopSheet.
  ///
  /// In en, this message translates to:
  /// **'Stop {title}'**
  String stopSheet(String title);

  /// No description provided for @shareSheet.
  ///
  /// In en, this message translates to:
  /// **'Share {title}'**
  String shareSheet(String title);

  /// No description provided for @lyricLine.
  ///
  /// In en, this message translates to:
  /// **'Line {line}'**
  String lyricLine(String line);

  /// No description provided for @clefName.
  ///
  /// In en, this message translates to:
  /// **'{clef} Clef'**
  String clefName(String clef);

  /// No description provided for @clefHeader.
  ///
  /// In en, this message translates to:
  /// **'{clef} clef'**
  String clefHeader(String clef);

  /// No description provided for @measureTimeSignature.
  ///
  /// In en, this message translates to:
  /// **'Measure {number} time signature'**
  String measureTimeSignature(int number);

  /// No description provided for @measureMeter.
  ///
  /// In en, this message translates to:
  /// **'Measure {number}: {beats}/{unit}'**
  String measureMeter(int number, int beats, int unit);

  /// No description provided for @measureCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} measure} other{{count} measures}}'**
  String measureCount(int count);

  /// No description provided for @musicVolume.
  ///
  /// In en, this message translates to:
  /// **'Music playback {percent}%'**
  String musicVolume(int percent);

  /// No description provided for @metronomeVolume.
  ///
  /// In en, this message translates to:
  /// **'Metronome {percent}%'**
  String metronomeVolume(int percent);

  /// No description provided for @cursorFromLeft.
  ///
  /// In en, this message translates to:
  /// **'{percent}% from left'**
  String cursorFromLeft(int percent);

  /// No description provided for @toleranceCents.
  ///
  /// In en, this message translates to:
  /// **'±{cents} cents'**
  String toleranceCents(int cents);

  /// No description provided for @microphoneStatus.
  ///
  /// In en, this message translates to:
  /// **'MICROPHONE: {status}'**
  String microphoneStatus(String status);

  /// No description provided for @pitchGaugeReading.
  ///
  /// In en, this message translates to:
  /// **'Pitch {description}; acceptable within plus or minus {cents} cents'**
  String pitchGaugeReading(String description, int cents);

  /// No description provided for @sharpCents.
  ///
  /// In en, this message translates to:
  /// **'{cents} cents sharp'**
  String sharpCents(int cents);

  /// No description provided for @flatCents.
  ///
  /// In en, this message translates to:
  /// **'{cents} cents flat'**
  String flatCents(int cents);

  /// No description provided for @onPitch.
  ///
  /// In en, this message translates to:
  /// **'on pitch'**
  String get onPitch;

  /// No description provided for @leftVolta.
  ///
  /// In en, this message translates to:
  /// **'Left volta: {number} (cycle 1, 2, 3, none)'**
  String leftVolta(String number);

  /// No description provided for @leftRepeat.
  ///
  /// In en, this message translates to:
  /// **'Toggle left repeat'**
  String get leftRepeat;

  /// No description provided for @rightVolta.
  ///
  /// In en, this message translates to:
  /// **'Right volta: {number} (cycle 1, 2, 3, none)'**
  String rightVolta(String number);

  /// No description provided for @rightRepeat.
  ///
  /// In en, this message translates to:
  /// **'Toggle right repeat'**
  String get rightRepeat;

  /// No description provided for @noVolta.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get noVolta;

  /// No description provided for @octaveLower.
  ///
  /// In en, this message translates to:
  /// **'{notation} · written notes stay in place · sounds {count, plural, one{{count} octave} other{{count} octaves}} lower'**
  String octaveLower(String notation, int count);

  /// No description provided for @octaveHigher.
  ///
  /// In en, this message translates to:
  /// **'{notation} · written notes stay in place · sounds {count, plural, one{{count} octave} other{{count} octaves}} higher'**
  String octaveHigher(String notation, int count);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @deviceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Device language'**
  String get deviceLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get spanish;

  /// No description provided for @languageHelp.
  ///
  /// In en, this message translates to:
  /// **'Follow your phone’s language or choose a language for this app.'**
  String get languageHelp;

  /// No description provided for @welcomeSpanish.
  ///
  /// In en, this message translates to:
  /// **'Partituras para Novatos'**
  String get welcomeSpanish;

  /// No description provided for @removeSheetQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove sheet?'**
  String get removeSheetQuestion;

  /// No description provided for @frames.
  ///
  /// In en, this message translates to:
  /// **'frames'**
  String get frames;

  /// No description provided for @noPitch.
  ///
  /// In en, this message translates to:
  /// **'No pitch'**
  String get noPitch;

  /// No description provided for @flat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get flat;

  /// No description provided for @sharp.
  ///
  /// In en, this message translates to:
  /// **'Sharp'**
  String get sharp;

  /// No description provided for @inTune.
  ///
  /// In en, this message translates to:
  /// **'In tune'**
  String get inTune;

  /// No description provided for @flatIndicator.
  ///
  /// In en, this message translates to:
  /// **'♭ Flat'**
  String get flatIndicator;

  /// No description provided for @sharpIndicator.
  ///
  /// In en, this message translates to:
  /// **'Sharp ♯'**
  String get sharpIndicator;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
