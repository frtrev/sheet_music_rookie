import 'package:xml/xml.dart';

XmlElement _el(
  String name, {
  String? text,
  Map<String, String> attrs = const {},
  List<XmlNode> children = const [],
}) => XmlElement(
  XmlName.parts(name),
  [for (final e in attrs.entries) XmlAttribute(XmlName.parts(e.key), e.value)],
  [if (text != null) XmlText(text), ...children],
);
String? _text(XmlElement element, String name) =>
    element.getElement(name)?.innerText.trim();
int? _int(XmlElement element, String name) =>
    int.tryParse(_text(element, name) ?? '');
int? _fractionTicks(String? value) {
  if (value == null) return null;
  final parts = value.split('/');
  if (parts.length != 2) return null;
  final n = int.tryParse(parts[0]);
  final d = int.tryParse(parts[1]);
  if (n == null || d == null || d == 0) return null;
  return (n * 1920 / d).round();
}

/// Converts the first pitched melody staff/voice from native MuseScore 3/4
/// into the same MusicXML import path used by the editor. Layout, mixer state,
/// extra staves and accompaniment are intentionally outside the melody model.
String museScoreToMusicXml(XmlDocument document) {
  final root = document.rootElement;
  final version = root.getAttribute('version') ?? '';
  if (!version.startsWith('3.') && !version.startsWith('4.')) {
    throw const FormatException(
      'This MuseScore version is not supported. Export it as MusicXML.',
    );
  }
  final score = root.getElement('Score');
  if (score == null) throw const FormatException('No MuseScore score found.');
  final staves = score
      .findElements('Staff')
      .where((s) => s.findAllElements('Chord').isNotEmpty)
      .toList();
  if (staves.isEmpty) {
    throw const FormatException('No melody notes found in the MuseScore file.');
  }
  final staff = staves.first;
  final measures = staff.findElements('Measure').toList();
  var voiceIndex = 0;
  for (final measure in measures) {
    final voices = measure.findElements('voice').toList();
    final index = voices.indexWhere((v) => v.findElements('Chord').isNotEmpty);
    if (index >= 0) {
      voiceIndex = index;
      break;
    }
  }
  final leftBars = List.generate(measures.length, (_) => <XmlElement>[]);
  final rightBars = List.generate(measures.length, (_) => <XmlElement>[]);
  XmlElement bar(String location, List<XmlNode> children) =>
      _el('barline', attrs: {'location': location}, children: children);
  for (final (i, measure) in measures.indexed) {
    if (measure.getElement('startRepeat') != null) {
      leftBars[i].add(
        bar('left', [
          _el('repeat', attrs: {'direction': 'forward'}),
        ]),
      );
    }
    if (measure.getElement('endRepeat') != null) {
      rightBars[i].add(
        bar('right', [
          _el(
            'repeat',
            attrs: {
              'direction': 'backward',
              'times': '${_int(measure, 'endRepeat') ?? 2}',
            },
          ),
        ]),
      );
    }
    for (final spanner
        in measure
            .findAllElements('Spanner')
            .where(
              (s) =>
                  s.getAttribute('type') == 'Volta' &&
                  s.getElement('Volta') != null,
            )) {
      final volta = spanner.getElement('Volta')!;
      final location = spanner.getElement('next')?.getElement('location');
      if (location == null) {
        throw const FormatException(
          'Unsupported MuseScore ending span. Export it as MusicXML.',
        );
      }
      final count = _int(location, 'measures') ?? 0;
      final fraction = _fractionTicks(_text(location, 'fractions')) ?? 0;
      final end = i + count - (fraction == 0 ? 1 : 0);
      if (end < i || end >= measures.length) {
        throw const FormatException('Invalid MuseScore ending span.');
      }
      final numbers = _text(volta, 'endings');
      if (numbers == null || numbers.isEmpty) {
        throw const FormatException('Missing MuseScore ending numbers.');
      }
      leftBars[i].add(
        bar('left', [
          _el('ending', attrs: {'number': numbers, 'type': 'start'}),
        ]),
      );
      rightBars[end].add(
        bar('right', [
          _el(
            'ending',
            attrs: {
              'number': numbers,
              'type': (_int(volta, 'endHookType') ?? 0) == 0
                  ? 'discontinue'
                  : 'stop',
            },
          ),
        ]),
      );
    }
  }

  var beats = 4;
  var unit = 4;
  final title = score
      .findElements('metaTag')
      .where((e) => e.getAttribute('name') == 'workTitle')
      .firstOrNull
      ?.innerText
      .trim();
  final nativeClef = staff.findAllElements('Clef').firstOrNull;
  final clefName = nativeClef == null
      ? (score
                .findElements('Part')
                .firstOrNull
                ?.findElements('Staff')
                .firstOrNull
                ?.getElement('defaultClef')
                ?.innerText ??
            'G')
      : (_text(nativeClef, 'concertClefType') ??
            _text(nativeClef, 'subtype') ??
            'G');
  if (!clefName.startsWith('G') && !clefName.startsWith('F')) {
    throw const FormatException('This MuseScore clef is not supported.');
  }
  final output = <XmlNode>[];
  for (final (i, measure) in measures.indexed) {
    final voices = measure.findElements('voice').toList();
    final voice = voices.isEmpty
        ? measure
        : (voiceIndex < voices.length ? voices[voiceIndex] : null);
    final time = voice?.getElement('TimeSig');
    beats = time == null ? beats : (_int(time, 'sigN') ?? beats);
    unit = time == null ? unit : (_int(time, 'sigD') ?? unit);
    if (beats <= 0 || unit <= 0) {
      throw const FormatException('Invalid MuseScore time signature.');
    }
    final capacity =
        _fractionTicks(measure.getAttribute('len')) ?? beats * 1920 ~/ unit;
    final attributes = <XmlNode>[_el('divisions', text: '480')];
    if (i == 0 || time != null) {
      attributes.add(
        _el(
          'time',
          children: [
            _el('beats', text: '$beats'),
            _el('beat-type', text: '$unit'),
          ],
        ),
      );
    }
    final key = voice?.getElement('KeySig');
    if (key != null) {
      attributes.add(
        _el(
          'key',
          children: [
            _el(
              'fifths',
              text:
                  '${_int(key, 'concertKey') ?? _int(key, 'accidental') ?? 0}',
            ),
          ],
        ),
      );
    }
    if (i == 0) {
      attributes.add(
        _el(
          'clef',
          children: [
            _el('sign', text: clefName.startsWith('F') ? 'F' : 'G'),
            _el('line', text: clefName.startsWith('F') ? '4' : '2'),
            if (clefName.contains('8vb')) _el('clef-octave-change', text: '-1'),
            if (clefName.contains('8va')) _el('clef-octave-change', text: '1'),
          ],
        ),
      );
    }
    final content = <XmlNode>[
      _el('attributes', children: attributes),
      ...leftBars[i],
    ];
    var used = 0;
    if (voice != null) {
      for (final item in voice.childElements) {
        final tag = item.name.local;
        if (tag == 'Tuplet' || item.getElement('Tuplet') != null) {
          throw const FormatException(
            'MuseScore tuplets are not supported yet. Export this score as MusicXML.',
          );
        }
        if (tag == 'Tempo') {
          final bpm = (double.tryParse(_text(item, 'tempo') ?? '') ?? 2) * 60;
          content.add(
            _el(
              'direction',
              children: [
                _el('sound', attrs: {'tempo': '${bpm.round()}'}),
              ],
            ),
          );
        }
        if (tag != 'Chord' && tag != 'Rest') continue;
        if (item.childElements.any(
          (e) =>
              e.name.local.startsWith('grace') ||
              ['acciaccatura', 'appoggiatura'].contains(e.name.local),
        )) {
          continue;
        }
        const durations = {
          'long': 7680,
          'breve': 3840,
          'whole': 1920,
          'half': 960,
          'quarter': 480,
          'eighth': 240,
          '16th': 120,
          '32nd': 60,
          '64th': 30,
        };
        final type = _text(item, 'durationType');
        var ticks = type == 'measure'
            ? (_fractionTicks(_text(item, 'duration')) ?? capacity)
            : durations[type];
        if (ticks == null) {
          throw FormatException('Unsupported MuseScore duration: $type.');
        }
        final base = ticks;
        final dots = _int(item, 'dots') ?? 0;
        for (var dot = 1; dot <= dots; dot++) {
          ticks = ticks! + (base ~/ (1 << dot));
        }
        final duration = ticks!;
        if (duration <= 0 || duration % 120 != 0) {
          throw const FormatException(
            'This score uses rhythms finer than the editor supports.',
          );
        }
        final noteContent = <XmlNode>[];
        if (tag == 'Rest') {
          noteContent.add(_el('rest'));
        } else {
          final nativeNote = item.getElement('Note');
          if (nativeNote == null) {
            throw const FormatException('Missing MuseScore note pitch.');
          }
          final pitch = _int(nativeNote, 'pitch');
          if (pitch == null || pitch < 0 || pitch > 127) {
            throw const FormatException('Invalid MuseScore note pitch.');
          }
          const names = ['C', 'G', 'D', 'A', 'E', 'B', 'F'];
          const naturalTpc = {
            'C': 14,
            'G': 15,
            'D': 16,
            'A': 17,
            'E': 18,
            'B': 19,
            'F': 13,
          };
          const pcs = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
          const defaultNames = [
            'C',
            'C',
            'D',
            'D',
            'E',
            'F',
            'F',
            'G',
            'G',
            'A',
            'A',
            'B',
          ];
          final tpc = _int(nativeNote, 'tpc') ?? _int(nativeNote, 'tpc1');
          final name = tpc == null ? defaultNames[pitch % 12] : names[tpc % 7];
          final alter = tpc == null
              ? pitch % 12 - pcs[name]!
              : (tpc - naturalTpc[name]!) ~/ 7;
          final octave = (pitch - pcs[name]! - alter) ~/ 12 - 1;
          noteContent.add(
            _el(
              'pitch',
              children: [
                _el('step', text: name),
                _el('alter', text: '$alter'),
                _el('octave', text: '$octave'),
              ],
            ),
          );
          final startsTie =
              nativeNote.getElement('Tie') != null ||
              nativeNote
                  .findElements('Spanner')
                  .any(
                    (s) =>
                        s.getAttribute('type') == 'Tie' &&
                        s.getElement('next') != null,
                  );
          if (startsTie) noteContent.add(_el('tie', attrs: {'type': 'start'}));
          noteContent.add(
            _el(
              'accidental',
              text: alter == 0
                  ? 'natural'
                  : alter < 0
                  ? 'flat'
                  : 'sharp',
            ),
          );
        }
        noteContent.addAll([
          _el('duration', text: '$duration'),
          _el('voice', text: '1'),
        ]);
        for (final lyric in item.findElements('Lyrics')) {
          final nativeText = lyric.getElement('text');
          final syllabic = _text(lyric, 'syllabic');
          noteContent.add(
            _el(
              'lyric',
              attrs: {'number': '${(_int(lyric, 'no') ?? 0) + 1}'},
              children: [
                if (syllabic != null) _el('syllabic', text: syllabic),
                if (nativeText != null) _el('text', text: nativeText.innerText),
                if ((_fractionTicks(_text(lyric, 'ticks_f')) ??
                        _int(lyric, 'ticks') ??
                        0) >
                    0)
                  _el('extend'),
              ],
            ),
          );
        }
        content.add(_el('note', children: noteContent));
        used += duration;
      }
    }
    if (used > capacity) {
      throw const FormatException(
        'MuseScore measure duration exceeds its time signature.',
      );
    }
    if (used < capacity) {
      content.add(
        _el(
          'note',
          children: [
            _el('rest'),
            _el('duration', text: '${capacity - used}'),
            _el('voice', text: '1'),
          ],
        ),
      );
    }
    content.addAll(rightBars[i]);
    output.add(
      _el('measure', attrs: {'number': '${i + 1}'}, children: content),
    );
  }
  return _el(
    'score-partwise',
    attrs: {'version': '4.0'},
    children: [
      if (title != null && title.isNotEmpty)
        _el('work', children: [_el('work-title', text: title)]),
      _el(
        'part-list',
        children: [
          _el(
            'score-part',
            attrs: {'id': 'P1'},
            children: [_el('part-name', text: 'Voice')],
          ),
        ],
      ),
      _el('part', attrs: {'id': 'P1'}, children: output),
    ],
  ).toXmlString();
}
