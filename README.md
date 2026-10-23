# Sheet Music Rookie

An offline Flutter prototype that turns a single sung melody into editable-ready musical data and dynamically rendered notation. Phase 1 supports treble and bass clefs, selectable octave ranges, all 15 standard major key signatures, live YIN pitch detection, syllable-aware note segmentation, rhythm quantization (including dotted values), automatic 4/4 measures, tied bar-line splits, piano-style score playback, a tempo-synchronized metronome, cursor-based punch-in recording, manual note insertion, and persistent recognition tuning.

Octave-clef ranges follow standard sounding-pitch direction: **8 up** writes the captured pitch one octave lower and plays it one octave above the written note; **8 down** writes it one octave higher and plays it one octave below. The same rule applies to manual notes and edit previews.

## Run

```sh
flutter pub get
flutter run
```

Use a physical iPhone or Android device for voice testing. Simulators can verify navigation and rendering, but their microphone input is not representative of device capture.

The editor requests microphone permission and starts listening automatically. If permission was previously denied, enable microphone access in the device's system settings and tap **Retry**.

Tap anywhere on the staff to place the shared score cursor. **Play** starts there, and **Record** punches in there: newly sung notes overwrite the same timeline span until silence is detected, later notes are retained, and the cursor lands where writing stopped. Repositioning the cursor during playback seeks immediately. Use **Insert Note** to choose a pitch, octave, and regular or dotted duration and place it at the cursor.

Use **Practice** to rehearse without changing the composition. Practice starts at the beginning and moves the cursor to the next note after the expected sounding pitch is stable and has been held for at least 60% of the written duration. The fixed gauge on the score's left edge moves up for sharp tones and down for flat tones, changing from red to green as the detected pitch approaches the current note. Tied fragments count as one note and rests are skipped. Record, Play, and Practice are exclusive transports: starting one stops either of the others.

Use the save button in the editor to name and store a composition locally. Scores are saved in the app's documents directory as compressed MusicXML (`.mxl`) archives, with a standard MusicXML 4.0 score plus private round-trip metadata for the editor. The **Open** button on the home screen lists saved scores and restores their notation and editable recording events. No cloud service or account is involved.

The installed mobile app also registers as a MusicXML document editor. From Files or another file manager, use **Open With** or **Share** and choose Sheet Music Rookie to import `.mxl`, `.musicxml`, or legacy `.xml` scores. App-authored MXL files retain all editor metadata; third-party partwise MusicXML imports the primary voice with its title, tempo, meter, key, clef, notes, rests, accidentals, and ties.

When the cursor is over a note, that note is highlighted and the edit bar below the staff becomes active. The up/down arrows transpose it by one semitone, while the left/right arrows choose the next shorter or longer supported duration. An upward alteration is written with a sharp and a downward alteration with a flat. That accidental remains active for the matching staff pitch through the measure, with a natural shown only when a later note cancels it; accidentals reset at the next bar line. Every edit previews only the resulting note for its complete duration without moving the score cursor.

The rest button in the same edit bar changes a selected note into an equal-duration rest. When a rest is selected, the button changes to a note icon and restores the clef's first-line pitch (E4 for treble or G2 for bass). At a blank cursor position within the current measure, the rest button inserts a quarter rest, shortened automatically when less space remains; any preceding blank gap is retained as silence.

Tap the key chip to choose C major, any of the seven sharp major keys, or any of the seven flat major keys. The signature is drawn on the staff and changes the affected written pitches during piano playback; an explicit natural cancels the signature for that note.

Tap the metronome chip to cycle through **On**, **Single**, and **Off**. On uses a stronger click on the first quarter note of each measure and regular clicks on the remaining beats; Single uses the same quiet “tsk” on every quarter note. The **Volumes** chip opens independent sliders for piano playback and metronome level. Recording-volume changes do not restart the beat grid. Recording uses one continuous click track with no decoder restart at measure boundaries, while playback mixes the click track directly into the piano audio so notes and clicks stay sample-aligned even when playback starts from the cursor. For repeated syllables such as “La, La, La,” open **Voice Detection Settings** and use **Optimize for “La, La, La”**. The optimized capture treats brief consonant gaps as separate onsets and measures repeated notes onset-to-onset for steadier rhythmic values.

## Verification

```sh
flutter analyze
flutter test
flutter build ios --simulator --no-codesign
flutter build apk --debug
```

Unit coverage includes synthetic A4 detection, stable-note segmentation, duration quantization, automatic measure creation, and tie creation. The widget smoke test covers the main menu and clef chooser.

## Architecture

- `lib/audio`: PCM capture, YIN pitch detection, smoothing, and note segmentation.
- `lib/transcription`: conversion of timestamped raw note events into tick-based notation and measures.
- `lib/models`: composition, raw detection, and notation data.
- `lib/notation`: a data-driven `CustomPainter` score renderer.
- `lib/services/score_playback_service.dart`: offline piano-style WAV synthesis and playback.
- `lib/screens` and `lib/widgets`: navigation, live diagnostics, controls, and tuning UI.
- `lib/services`: local settings persistence.

No network, backend, account, AI model, or cloud service is used.
