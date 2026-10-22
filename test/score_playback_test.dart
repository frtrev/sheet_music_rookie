import 'package:flutter_test/flutter_test.dart';
import 'package:sheet_music_rookie/models/composition.dart';
import 'package:sheet_music_rookie/models/measure.dart';
import 'package:sheet_music_rookie/models/musical_note.dart';
import 'package:sheet_music_rookie/services/score_playback_service.dart';
import 'package:sheet_music_rookie/services/metronome_service.dart';

void main() {
  test('piano synthesizer creates a playable WAV from notation', () {
    const composition = Composition(
      clef: ClefType.treble,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(midiPitch: 60, startTick: 0, durationTicks: 480),
            MusicalNote(midiPitch: 64, startTick: 480, durationTicks: 960),
          ],
        ),
      ],
    );

    final wave = const PianoWaveSynthesizer(sampleRate: 8000)
        .render(composition);

    expect(wave, isNotNull);
    expect(String.fromCharCodes(wave!.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wave.sublist(8, 12)), 'WAVE');
    expect(wave.length, greaterThan(44));
  });

  test('empty notation does not create playback audio', () {
    const composition = Composition(clef: ClefType.bass);
    expect(const PianoWaveSynthesizer().render(composition), isNull);
  });

  test('octave-clef playback follows the selected direction', () {
    const writtenMidi = 60;
    const up = Composition(
      clef: ClefType.treble,
      octaveRange: OctaveRange.octaveUp,
    );
    const down = Composition(
      clef: ClefType.treble,
      octaveRange: OctaveRange.octaveDown,
    );

    expect(playbackMidiPitch(up, writtenMidi), 72);
    expect(playbackMidiPitch(down, writtenMidi), 48);
  });

  test('key signatures alter natural notes unless cancelled', () {
    const gMajor = Composition(
      clef: ClefType.treble,
      keySignature: KeySignature.gMajor,
    );
    const fMajor = Composition(
      clef: ClefType.treble,
      keySignature: KeySignature.fMajor,
    );

    expect(playbackMidiPitch(gMajor, 65), 66); // F becomes F♯.
    expect(
      playbackMidiPitch(gMajor, 65, accidental: NoteAccidental.natural),
      65,
    );
    expect(playbackMidiPitch(fMajor, 71), 70); // B becomes B♭.
  });

  test('rests retain silent time in synthesized playback', () {
    const sampleRate = 8000;
    const composition = Composition(
      clef: ClefType.treble,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(midiPitch: 60, startTick: 0, durationTicks: 480),
            MusicalNote(
              midiPitch: 0,
              startTick: 480,
              durationTicks: 480,
              isRest: true,
            ),
          ],
        ),
      ],
    );

    final wave = const PianoWaveSynthesizer(sampleRate: sampleRate)
        .render(composition);
    expect(wave, isNotNull);
    expect(wave!.length, 44 + sampleRate * 2);
  });

  test('metronome synthesizer creates an exact four-beat looping bar', () {
    const sampleRate = 8000;
    final wave = const MetronomeWaveSynthesizer(sampleRate: sampleRate)
        .render(120);

    expect(String.fromCharCodes(wave.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wave.sublist(8, 12)), 'WAVE');
    // Four beats at 120 BPM are two seconds, with 16-bit mono samples.
    expect(wave.length, 44 + sampleRate * 2 * 2);
  });
}
