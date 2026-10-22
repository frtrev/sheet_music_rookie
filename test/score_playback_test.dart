import 'dart:math' as math;
import 'dart:typed_data';

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
        .render(120, MetronomeMode.accented);

    expect(String.fromCharCodes(wave.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wave.sublist(8, 12)), 'WAVE');
    // Four beats at 120 BPM are two seconds, with 16-bit mono samples.
    expect(wave.length, 44 + sampleRate * 2 * 2);
  });

  test('recording click track has no audio boundary after beat four', () {
    const sampleRate = 8000;
    final wave = const MetronomeWaveSynthesizer(sampleRate: sampleRate)
        .render(120, MetronomeMode.single, measureCount: 2);
    final data = ByteData.sublistView(wave);
    const fifthBeatStart = 16000;
    final fifthBeatHasClick = [
      for (var offset = 1; offset < 100; offset++)
        data.getInt16(44 + (fifthBeatStart + offset) * 2, Endian.little),
    ].any((sample) => sample != 0);

    expect(wave.length, 44 + sampleRate * 2 * 4);
    expect(fifthBeatHasClick, isTrue);
  });

  test('single metronome produces equal low clicks on every quarter', () {
    const sampleRate = 8000;
    final single = const MetronomeWaveSynthesizer(sampleRate: sampleRate)
        .render(120, MetronomeMode.single);
    final accented = const MetronomeWaveSynthesizer(sampleRate: sampleRate)
        .render(120, MetronomeMode.accented);
    final singleData = ByteData.sublistView(single);
    final accentedData = ByteData.sublistView(accented);
    const samplesPerBeat = 4000;

    int peak(ByteData data, int beat) {
      var result = 0;
      for (var index = 1; index < 160; index++) {
        result = math.max(
          result,
          data
              .getInt16(44 + (beat * samplesPerBeat + index) * 2, Endian.little)
              .abs(),
        );
      }
      return result;
    }

    final singlePeaks = [
      for (var beat = 0; beat < 4; beat++) peak(singleData, beat),
    ];
    expect(singlePeaks.every((value) => value > 0), isTrue);
    expect(
      singlePeaks.reduce(math.max) - singlePeaks.reduce(math.min),
      lessThan(3),
    );
    expect(singlePeaks.first, lessThan(peak(accentedData, 0)));
    expect(peak(accentedData, 0), greaterThan(peak(accentedData, 1)));
  });

  test('score playback mixes metronome clicks onto the note timeline', () {
    const sampleRate = 8000;
    const composition = Composition(
      clef: ClefType.treble,
      metronomeMode: MetronomeMode.single,
      measures: [
        Measure(
          index: 0,
          notes: [
            MusicalNote(
              midiPitch: 0,
              startTick: 0,
              durationTicks: 1920,
              isRest: true,
            ),
          ],
        ),
      ],
    );
    final wave = const PianoWaveSynthesizer(sampleRate: sampleRate)
        .render(composition)!;
    final data = ByteData.sublistView(wave);

    for (final beatStart in [0, 4000, 8000, 12000]) {
      final hasClick = [
        for (var offset = 1; offset < 100; offset++)
          data.getInt16(44 + (beatStart + offset) * 2, Endian.little),
      ].any((sample) => sample != 0);
      expect(hasClick, isTrue);
    }
  });

  test('music and metronome gains are independently applied', () {
    const sampleRate = 8000;
    const note = MusicalNote(midiPitch: 60, startTick: 0, durationTicks: 480);
    const rest = MusicalNote(
      midiPitch: 0,
      startTick: 0,
      durationTicks: 480,
      isRest: true,
    );
    const synthesizer = PianoWaveSynthesizer(sampleRate: sampleRate);

    int peak(Uint8List wave) {
      final data = ByteData.sublistView(wave);
      var result = 0;
      for (var offset = 44; offset < wave.length; offset += 2) {
        result = math.max(result, data.getInt16(offset, Endian.little).abs());
      }
      return result;
    }

    final loudMusic = synthesizer.render(
      const Composition(
        clef: ClefType.treble,
        playbackVolume: 1,
        measures: [
          Measure(index: 0, notes: [note]),
        ],
      ),
    )!;
    final quietMusic = synthesizer.render(
      const Composition(
        clef: ClefType.treble,
        playbackVolume: .2,
        measures: [
          Measure(index: 0, notes: [note]),
        ],
      ),
    )!;
    final loudClick = synthesizer.render(
      const Composition(
        clef: ClefType.treble,
        metronomeMode: MetronomeMode.single,
        metronomeVolume: 1,
        measures: [
          Measure(index: 0, notes: [rest]),
        ],
      ),
    )!;
    final quietClick = synthesizer.render(
      const Composition(
        clef: ClefType.treble,
        metronomeMode: MetronomeMode.single,
        metronomeVolume: .2,
        measures: [
          Measure(index: 0, notes: [rest]),
        ],
      ),
    )!;

    expect(peak(quietMusic), lessThan(peak(loudMusic)));
    expect(peak(quietClick), lessThan(peak(loudClick)));
  });
}
