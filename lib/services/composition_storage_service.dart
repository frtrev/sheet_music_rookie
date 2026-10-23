import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/composition.dart';
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
    final measures = const MeasureBuilder().build(
      rawEvents,
      tempo,
      beats,
      octaveTranspositionSemitones: octaveRange.semitones,
      keySignature: keySignature,
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
  };

  RawNoteEvent _rawEventFromJson(Map<String, dynamic> data) => RawNoteEvent(
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
    for (final measure in composition.measures) {
      buffer.writeln('    <measure number="${measure.index + 1}">');
      if (measure.index == 0) {
        buffer
          ..writeln('      <attributes>')
          ..writeln('        <divisions>480</divisions>')
          ..writeln(
            '        <key><fifths>${composition.keySignature.accidentalCount}</fifths><mode>major</mode></key>',
          )
          ..writeln(
            '        <time><beats>${composition.beatsPerMeasure}</beats><beat-type>${composition.beatUnit}</beat-type></time>',
          )
          ..writeln(
            '        <clef><sign>${composition.clef == ClefType.treble ? 'G' : 'F'}</sign><line>${composition.clef == ClefType.treble ? 2 : 4}</line></clef>',
          )
          ..writeln('      </attributes>')
          ..writeln(
            '      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>${composition.tempoBpm}</per-minute></metronome></direction-type><sound tempo="${composition.tempoBpm}"/></direction>',
          );
      }
      for (final note in measure.notes) {
        _writeMusicXmlNote(buffer, composition, note);
      }
      buffer.writeln('    </measure>');
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
      octave: naturalMidi ~/ 12 - 1,
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
