import '../models/note_lyric.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../models/composition.dart';
import '../models/measure.dart';
import '../models/musical_note.dart';
import '../models/raw_note_event.dart';
import '../transcription/measure_builder.dart';

const _mxlMimeType = 'application/vnd.recordare.musicxml';
const _musicXmlMimeType = 'application/vnd.recordare.musicxml+xml';
const _scorePath = 'score.musicxml';
const _appDataPath = 'sheet-music-rookie.json';

class SavedComposition {
  const SavedComposition({
    required this.path,
    required this.composition,
    required this.rawEvents,
    required this.modifiedAt,
  });

  final String path;
  final Composition composition;
  final List<RawNoteEvent> rawEvents;
  final DateTime modifiedAt;
}

class CompositionStorageService {
  CompositionStorageService({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<SavedComposition> save({
    required Composition composition,
    required List<RawNoteEvent> rawEvents,
    String? existingPath,
  }) async {
    final directory = await _storageDirectory();
    final path =
        existingPath ?? await _availablePath(directory, composition.title);
    final savedAt = DateTime.now();
    final archive = Archive()
      ..addFile(
        ArchiveFile.noCompress(
          'mimetype',
          _mxlMimeType.length,
          ascii.encode(_mxlMimeType),
        ),
      )
      ..addFile(ArchiveFile.string('META-INF/container.xml', _containerXml))
      ..addFile(ArchiveFile.string(_scorePath, _musicXml(composition)))
      ..addFile(
        ArchiveFile.string(
          _appDataPath,
          jsonEncode(_appData(composition, rawEvents, savedAt)),
        ),
      );
    final bytes = ZipEncoder().encodeBytes(archive, level: 9);
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return SavedComposition(
      path: path,
      composition: composition,
      rawEvents: List.unmodifiable(rawEvents),
      modifiedAt: savedAt,
    );
  }

  Future<List<SavedComposition>> listSaved() async {
    final directory = await _storageDirectory();
    final saved = <SavedComposition>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.mxl')) {
        continue;
      }
      try {
        saved.add(await load(entity.path));
      } on Object {
        // Ignore damaged or unrelated files rather than blocking the library.
      }
    }
    saved.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return saved;
  }

  Future<SavedComposition> load(String path) async {
    final file = File(path);
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final mime = archive.findFile('mimetype');
    final appData = archive.findFile(_appDataPath);
    final score = archive.findFile(_scorePath);
    if (mime == null ||
        ascii.decode(mime.content) != _mxlMimeType ||
        score == null ||
        appData == null) {
      throw const FormatException('Unsupported compressed MusicXML file.');
    }
    final data = jsonDecode(utf8.decode(appData.content));
    if (data is! Map<String, dynamic> || data['formatVersion'] != 1) {
      throw const FormatException('Unsupported saved composition version.');
    }
    final rawEvents = (data['rawEvents'] as List<dynamic>)
        .map((value) => _rawEventFromJson(value as Map<String, dynamic>))
        .toList();
    final clef = ClefType.values.byName(data['clef'] as String);
    final octaveRange = OctaveRange.values.byName(
      data['octaveRange'] as String,
    );
    final keyCount = data['keySignatureFifths'] as int;
    final keySignature = KeySignature.values.firstWhere(
      (value) => value.accidentalCount == keyCount,
    );
    final tempo = data['tempoBpm'] as int;
    final beats = data['beatsPerMeasure'] as int;
    final beatUnit = data['beatUnit'] as int;
    final storedMeasureSignatures = data['measureSignatures'] as List<dynamic>?;
    final measureTemplates = storedMeasureSignatures == null
        ? const <Measure>[]
        : [
            for (final (index, value) in storedMeasureSignatures.indexed)
              Measure(
                index: index,
                beatsPerMeasure:
                    (value as Map<String, dynamic>)['beatsPerMeasure'] as int,
                beatUnit: value['beatUnit'] as int,
              ),
          ];
    final measures = const MeasureBuilder().build(
      rawEvents,
      tempo,
      beats,
      beatUnit: beatUnit,
      octaveTranspositionSemitones: octaveRange.semitones,
      keySignature: keySignature,
      measureTemplates: measureTemplates,
      addTrailingMeasure: measureTemplates.isEmpty,
    );
    final composition = Composition(
      title: data['title'] as String,
      keySignature: keySignature,
      beatsPerMeasure: beats,
      beatUnit: beatUnit,
      tempoBpm: tempo,
      clef: clef,
      octaveRange: octaveRange,
      recordingMode: RecordingMode.values.byName(
        data['recordingMode'] as String,
      ),
      metronomeMode: MetronomeMode.values.byName(
        data['metronomeMode'] as String,
      ),
      metronomeVolume: (data['metronomeVolume'] as num).toDouble(),
      playbackVolume: (data['playbackVolume'] as num).toDouble(),
      microphoneActive: false,
      measures: measures,
    );
    final stat = await file.stat();
    final encodedDate = DateTime.tryParse(data['savedAt'] as String? ?? '');
    return SavedComposition(
      path: path,
      composition: composition,
      rawEvents: rawEvents,
      modifiedAt: encodedDate ?? stat.modified,
    );
  }

  /// Imports either an uncompressed MusicXML document or an MXL container.
  /// Files saved by this app use their lossless editor metadata; ordinary
  /// MusicXML scores are converted into the app's monophonic event model.
  Future<SavedComposition> importFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.findFile(_appDataPath) != null) {
        return load(path);
      }
      final scoreFile = _scoreFileIn(archive);
      if (scoreFile == null) {
        throw const FormatException('No MusicXML score was found in the MXL.');
      }
      return _importMusicXml(
        utf8.decode(scoreFile.content),
        path,
        await file.stat(),
      );
    }
    return _importMusicXml(utf8.decode(bytes), path, await file.stat());
  }

  ArchiveFile? _scoreFileIn(Archive archive) {
    final container = archive.findFile('META-INF/container.xml');
    if (container != null) {
      final document = XmlDocument.parse(utf8.decode(container.content));
      final rootfile = document.findAllElements('rootfile').firstOrNull;
      final fullPath = rootfile?.getAttribute('full-path');
      if (fullPath != null) return archive.findFile(fullPath);
    }
    for (final file in archive.files) {
      final name = file.name.toLowerCase();
      if (file.isFile &&
          !name.startsWith('meta-inf/') &&
          (name.endsWith('.musicxml') || name.endsWith('.xml'))) {
        return file;
      }
    }
    return null;
  }

  SavedComposition _importMusicXml(String source, String path, FileStat stat) {
    final document = XmlDocument.parse(source);
    if (document.rootElement.name.local != 'score-partwise') {
      throw const FormatException(
        'Only partwise MusicXML scores are supported.',
      );
    }
    final part = document.findAllElements('part').firstOrNull;
    if (part == null) {
      throw const FormatException('The score has no music part.');
    }

    final notes = part.findAllElements('note').toList();
    final primaryVoice = notes
        .map((note) => note.getElement('voice')?.innerText.trim())
        .whereType<String>()
        .where((voice) => voice.isNotEmpty)
        .fold<String?>(null, (current, voice) {
          if (voice == '1') return '1';
          return current ?? voice;
        });
    var divisions = 1;
    var beats = 4;
    var beatUnit = 4;
    var tempo = 120;
    var clef = ClefType.treble;
    var octaveRange = OctaveRange.standard;
    var keySignature = KeySignature.cMajor;

    final divisionsText = document.findAllElements('divisions').firstOrNull;
    divisions = _positiveInt(divisionsText?.innerText, fallback: divisions);
    final beatsText = document.findAllElements('beats').firstOrNull;
    beats = _positiveInt(beatsText?.innerText, fallback: beats);
    final beatTypeText = document.findAllElements('beat-type').firstOrNull;
    beatUnit = _positiveInt(beatTypeText?.innerText, fallback: beatUnit);
    final fifthsText = document.findAllElements('fifths').firstOrNull;
    final fifths = int.tryParse(fifthsText?.innerText.trim() ?? '') ?? 0;
    keySignature = KeySignature.values.firstWhere(
      (key) => key.accidentalCount == fifths.clamp(-7, 7),
    );
    final firstClef = part.findAllElements('clef').firstOrNull;
    final clefSign = firstClef
        ?.getElement('sign')
        ?.innerText
        .trim()
        .toUpperCase();
    if (clefSign == 'F') clef = ClefType.bass;
    final clefOctaveChange = int.tryParse(
      firstClef?.getElement('clef-octave-change')?.innerText.trim() ?? '',
    );
    octaveRange = switch (clefOctaveChange) {
      -2 => OctaveRange.twoOctavesDown,
      -1 => OctaveRange.octaveDown,
      1 => OctaveRange.octaveUp,
      2 => OctaveRange.twoOctavesUp,
      _ => OctaveRange.standard,
    };
    final soundTempo = document
        .findAllElements('sound')
        .map((element) => double.tryParse(element.getAttribute('tempo') ?? ''))
        .whereType<double>()
        .firstOrNull;
    final metronomeTempo = double.tryParse(
      document.findAllElements('per-minute').firstOrNull?.innerText.trim() ??
          '',
    );
    tempo = ((soundTempo ?? metronomeTempo ?? tempo).round()).clamp(20, 400);

    final xmlMeasures = part.findElements('measure').toList();
    final measureTemplates = <Measure>[];
    var activeBeats = beats;
    var activeBeatUnit = beatUnit;
    for (final (index, xmlMeasure) in xmlMeasures.indexed) {
      final localBeats = xmlMeasure
          .findElements('attributes')
          .expand((attributes) => attributes.findElements('time'))
          .expand((time) => time.findElements('beats'))
          .firstOrNull;
      final localBeatUnit = xmlMeasure
          .findElements('attributes')
          .expand((attributes) => attributes.findElements('time'))
          .expand((time) => time.findElements('beat-type'))
          .firstOrNull;
      activeBeats = _positiveInt(localBeats?.innerText, fallback: activeBeats);
      activeBeatUnit = _positiveInt(
        localBeatUnit?.innerText,
        fallback: activeBeatUnit,
      );
      var measureTicks = 0;
      for (final note in xmlMeasure.findElements('note')) {
        if (note.getElement('chord') != null ||
            note.getElement('grace') != null) {
          continue;
        }
        final voice = note.getElement('voice')?.innerText.trim();
        if (primaryVoice != null && voice != null && voice != primaryVoice) {
          continue;
        }
        final units = int.tryParse(
          note.getElement('duration')?.innerText.trim() ?? '',
        );
        if (units != null && units > 0) {
          measureTicks += (units * 480 / divisions).round();
        }
      }
      var measureBeats = activeBeats;
      var measureBeatUnit = activeBeatUnit;
      final nominalTicks = activeBeats * 1920 ~/ activeBeatUnit;
      if (index == 0 && measureTicks > 0 && measureTicks < nominalTicks) {
        final inferred = _timeSignatureForTicks(
          measureTicks,
          preferredBeatUnit: activeBeatUnit,
        );
        measureBeats = inferred.$1;
        measureBeatUnit = inferred.$2;
      }
      measureTemplates.add(
        Measure(
          index: index,
          beatsPerMeasure: measureBeats,
          beatUnit: measureBeatUnit,
        ),
      );
    }

    final rawEvents = <RawNoteEvent>[];
    var timestampMs = 0;
    for (final note in notes) {
      if (note.getElement('chord') != null ||
          note.getElement('grace') != null) {
        continue;
      }
      final voice = note.getElement('voice')?.innerText.trim();
      if (primaryVoice != null && voice != null && voice != primaryVoice) {
        continue;
      }
      final durationUnits = int.tryParse(
        note.getElement('duration')?.innerText.trim() ?? '',
      );
      if (durationUnits == null || durationUnits <= 0) continue;
      final ticks = (durationUnits * 480 / divisions).round().clamp(1, 7680);
      final durationMs = (ticks * 60000 / (tempo * 480)).round().clamp(
        1,
        60000,
      );
      final isRest = note.getElement('rest') != null;
      var midi = 0;
      var frequency = 0.0;
      if (!isRest) {
        final pitch = note.getElement('pitch');
        final step = pitch?.getElement('step')?.innerText.trim().toUpperCase();
        final octave = int.tryParse(
          pitch?.getElement('octave')?.innerText.trim() ?? '',
        );
        if (step == null || octave == null) continue;
        const naturalPitchClass = {
          'C': 0,
          'D': 2,
          'E': 4,
          'F': 5,
          'G': 7,
          'A': 9,
          'B': 11,
        };
        final natural = naturalPitchClass[step];
        if (natural == null) continue;
        final alter = double.tryParse(
          pitch?.getElement('alter')?.innerText.trim() ?? '0',
        );
        final soundingMidi = (octave + 1) * 12 + natural + (alter ?? 0).round();
        // MusicXML pitch data remains the sounding pitch. The transposing
        // clef changes where that pitch is written on the staff.
        midi = soundingMidi.clamp(0, 127);
        frequency = (440 * math.pow(2, (midi - 69) / 12)).toDouble();
      }
      final accidentalText = note
          .getElement('accidental')
          ?.innerText
          .trim()
          .toLowerCase();
      final accidental = switch (accidentalText) {
        'sharp' => NoteAccidental.sharp,
        'flat' => NoteAccidental.flat,
        'natural' => NoteAccidental.natural,
        _ => isRest ? NoteAccidental.none : NoteAccidental.automatic,
      };
      final tieToNext = note
          .findElements('tie')
          .any((tie) => tie.getAttribute('type') == 'start');
      rawEvents.add(
        RawNoteEvent(
          lyrics: [
            for (final lyric in note.findElements('lyric'))
              NoteLyric(lyric.toXmlString()),
          ],
          startTimeMs: timestampMs,
          endTimeMs: timestampMs + durationMs,
          frequencyHz: frequency,
          midiPitch: midi,
          confidence: 1,
          accidental: accidental,
          isRest: isRest,
          tieToNext: !isRest && tieToNext,
        ),
      );
      timestampMs += durationMs;
    }
    if (rawEvents.isEmpty) {
      throw const FormatException('The score contains no supported notes.');
    }

    final title =
        document.findAllElements('work-title').firstOrNull?.innerText.trim() ??
        document
            .findAllElements('movement-title')
            .firstOrNull
            ?.innerText
            .trim();
    final fallbackTitle = path
        .split(Platform.pathSeparator)
        .last
        .replaceFirst(
          RegExp(r'\.(mxl|musicxml|xml)$', caseSensitive: false),
          '',
        );
    final composition = Composition(
      title: title == null || title.isEmpty ? fallbackTitle : title,
      keySignature: keySignature,
      beatsPerMeasure: beats,
      beatUnit: beatUnit,
      tempoBpm: tempo,
      clef: clef,
      octaveRange: octaveRange,
      microphoneActive: false,
      measures: const MeasureBuilder().build(
        rawEvents,
        tempo,
        beats,
        beatUnit: beatUnit,
        octaveTranspositionSemitones: octaveRange.semitones,
        keySignature: keySignature,
        measureTemplates: measureTemplates,
        addTrailingMeasure: false,
      ),
    );
    return SavedComposition(
      path: path,
      composition: composition,
      rawEvents: rawEvents,
      modifiedAt: stat.modified,
    );
  }

  int _positiveInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0 ? fallback : parsed;
  }

  (int, int) _timeSignatureForTicks(
    int ticks, {
    required int preferredBeatUnit,
  }) {
    for (final unit in {preferredBeatUnit, 4, 8, 2, 16, 1}) {
      final scaled = ticks * unit;
      if (scaled % 1920 == 0) return (scaled ~/ 1920, unit);
    }
    return ((ticks / 480).ceil().clamp(1, 32).toInt(), 4);
  }

  Future<Directory> _storageDirectory() async {
    final documents = await _documentsDirectory();
    final directory = Directory('${documents.path}/compositions');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> _availablePath(Directory directory, String title) async {
    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final base = safeTitle.isEmpty ? 'Untitled Composition' : safeTitle;
    var candidate = '${directory.path}/$base.mxl';
    var suffix = 2;
    while (await File(candidate).exists()) {
      candidate = '${directory.path}/$base ($suffix).mxl';
      suffix++;
    }
    return candidate;
  }

  Map<String, dynamic> _appData(
    Composition composition,
    List<RawNoteEvent> events,
    DateTime savedAt,
  ) => {
    'formatVersion': 1,
    'savedAt': savedAt.toIso8601String(),
    'title': composition.title,
    'clef': composition.clef.name,
    'octaveRange': composition.octaveRange.name,
    'keySignatureFifths': composition.keySignature.accidentalCount,
    'beatsPerMeasure': composition.beatsPerMeasure,
    'beatUnit': composition.beatUnit,
    'measureSignatures': [
      for (final measure in composition.measures)
        {
          'beatsPerMeasure': measure.effectiveBeats(
            composition.beatsPerMeasure,
          ),
          'beatUnit': measure.effectiveBeatUnit(composition.beatUnit),
        },
    ],
    'tempoBpm': composition.tempoBpm,
    'recordingMode': composition.recordingMode.name,
    'metronomeMode': composition.metronomeMode.name,
    'metronomeVolume': composition.metronomeVolume,
    'playbackVolume': composition.playbackVolume,
    'rawEvents': [for (final event in events) _rawEventToJson(event)],
  };

  Map<String, dynamic> _rawEventToJson(RawNoteEvent event) => {
    'startTimeMs': event.startTimeMs,
    'endTimeMs': event.endTimeMs,
    'frequencyHz': event.frequencyHz,
    'midiPitch': event.midiPitch,
    'confidence': event.confidence,
    'accidental': event.accidental.name,
    'isRest': event.isRest,
    'tieToNext': event.tieToNext,
    'lyrics': [for (final lyric in event.lyrics) lyric.xml],
  };

  RawNoteEvent _rawEventFromJson(Map<String, dynamic> data) => RawNoteEvent(
    lyrics: [
      for (final xml in (data['lyrics'] as List? ?? const []))
        NoteLyric(xml as String),
    ],
    startTimeMs: data['startTimeMs'] as int,
    endTimeMs: data['endTimeMs'] as int,
    frequencyHz: (data['frequencyHz'] as num).toDouble(),
    midiPitch: data['midiPitch'] as int,
    confidence: (data['confidence'] as num).toDouble(),
    accidental: NoteAccidental.values.byName(data['accidental'] as String),
    isRest: data['isRest'] as bool,
    tieToNext: data['tieToNext'] as bool,
  );

  String _musicXml(Composition composition) {
    final clefOctaveChange = composition.octaveRange.semitones ~/ 12;
    final clefOctaveXml = clefOctaveChange == 0
        ? ''
        : '<clef-octave-change>$clefOctaveChange</clef-octave-change>';
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
      ..writeln(
        '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
      )
      ..writeln('<score-partwise version="4.0">')
      ..writeln(
        '  <work><work-title>${_xml(composition.title)}</work-title></work>',
      )
      ..writeln(
        '  <identification><encoding><software>Sheet Music Rookie</software></encoding></identification>',
      )
      ..writeln(
        '  <part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>',
      )
      ..writeln('  <part id="P1">');
    int? previousBeats;
    int? previousBeatUnit;
    for (final measure in composition.measures) {
      final measureBeats = measure.effectiveBeats(composition.beatsPerMeasure);
      final measureBeatUnit = measure.effectiveBeatUnit(composition.beatUnit);
      final pickup =
          measure.index == 0 &&
          (measureBeats != composition.beatsPerMeasure ||
              measureBeatUnit != composition.beatUnit);
      buffer.writeln(
        '    <measure number="${measure.index + 1}"${pickup ? ' implicit="yes"' : ''}>',
      );
      final timeChanged =
          measureBeats != previousBeats || measureBeatUnit != previousBeatUnit;
      if (measure.index == 0 || timeChanged) {
        buffer.writeln('      <attributes>');
        if (measure.index == 0) {
          buffer
            ..writeln('        <divisions>480</divisions>')
            ..writeln(
              '        <key><fifths>${composition.keySignature.accidentalCount}</fifths><mode>major</mode></key>',
            );
        }
        if (timeChanged) {
          buffer.writeln(
            '        <time><beats>$measureBeats</beats><beat-type>$measureBeatUnit</beat-type></time>',
          );
        }
        if (measure.index == 0) {
          buffer.writeln(
            '        <clef><sign>${composition.clef == ClefType.treble ? 'G' : 'F'}</sign><line>${composition.clef == ClefType.treble ? 2 : 4}</line>$clefOctaveXml</clef>',
          );
        }
        buffer.writeln('      </attributes>');
      }
      if (measure.index == 0) {
        buffer.writeln(
          '      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>${composition.tempoBpm}</per-minute></metronome></direction-type><sound tempo="${composition.tempoBpm}"/></direction>',
        );
      }
      for (final note in measure.notes) {
        _writeMusicXmlNote(buffer, composition, note);
      }
      buffer.writeln('    </measure>');
      previousBeats = measureBeats;
      previousBeatUnit = measureBeatUnit;
    }
    buffer
      ..writeln('  </part>')
      ..writeln('</score-partwise>');
    return buffer.toString();
  }

  void _writeMusicXmlNote(
    StringBuffer buffer,
    Composition composition,
    MusicalNote note,
  ) {
    buffer.writeln('      <note>');
    if (note.isRest) {
      buffer.writeln('        <rest/>');
    } else {
      final pitch = _writtenPitch(composition, note);
      buffer
        ..writeln('        <pitch>')
        ..writeln('          <step>${pitch.step}</step>');
      if (pitch.alter != 0) {
        buffer.writeln('          <alter>${pitch.alter}</alter>');
      }
      buffer
        ..writeln('          <octave>${pitch.octave}</octave>')
        ..writeln('        </pitch>');
    }
    if (note.tieFromPrevious) buffer.writeln('        <tie type="stop"/>');
    if (note.tieToNext) buffer.writeln('        <tie type="start"/>');
    buffer
      ..writeln('        <duration>${note.durationTicks}</duration>')
      ..writeln('        <voice>1</voice>')
      ..writeln('        <type>${_musicXmlType(note.value.baseTicks)}</type>');
    if (note.value.isDotted) buffer.writeln('        <dot/>');
    final accidental = switch (note.accidental) {
      NoteAccidental.sharp => 'sharp',
      NoteAccidental.flat => 'flat',
      NoteAccidental.natural => 'natural',
      _ => null,
    };
    if (accidental != null) {
      buffer.writeln('        <accidental>$accidental</accidental>');
    }
    if (note.tieFromPrevious || note.tieToNext) {
      buffer.writeln('        <notations>');
      if (note.tieFromPrevious) {
        buffer.writeln('          <tied type="stop"/>');
      }
      if (note.tieToNext) {
        buffer.writeln('          <tied type="start"/>');
      }
      buffer.writeln('        </notations>');
    }
    for (final lyric in note.lyrics) {
      buffer.writeln(lyric.xml);
    }
    buffer.writeln('      </note>');
  }

  ({String step, int alter, int octave}) _writtenPitch(
    Composition composition,
    MusicalNote note,
  ) {
    const naturalNames = {
      0: 'C',
      2: 'D',
      4: 'E',
      5: 'F',
      7: 'G',
      9: 'A',
      11: 'B',
    };
    final pitchClass = note.midiPitch % 12;
    final black = const {1, 3, 6, 8, 10}.contains(pitchClass);
    final naturalPitchClass = black
        ? (note.flatSpelling ? (pitchClass + 1) % 12 : (pitchClass + 11) % 12)
        : pitchClass;
    final naturalMidi =
        note.midiPitch + (black ? (note.flatSpelling ? 1 : -1) : 0);
    final alter = black
        ? (note.flatSpelling ? -1 : 1)
        : note.accidental == NoteAccidental.natural
        ? 0
        : composition.keySignature.alterationForNaturalPitchClass(
            naturalPitchClass,
          );
    return (
      step: naturalNames[naturalPitchClass]!,
      alter: alter,
      // Transposing clefs export sounding pitch data while displaying the
      // note at the app's written octave.
      octave: naturalMidi ~/ 12 - 1 + composition.octaveRange.semitones ~/ 12,
    );
  }

  String _musicXmlType(int baseTicks) => switch (baseTicks) {
    1920 => 'whole',
    960 => 'half',
    480 => 'quarter',
    240 => 'eighth',
    _ => '16th',
  };

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

const _containerXml =
    '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="score.musicxml" media-type="$_musicXmlMimeType"/>
  </rootfiles>
</container>
''';
