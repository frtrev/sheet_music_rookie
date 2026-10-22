import 'musical_note.dart';

class Measure {
  const Measure({required this.index, this.notes = const []});

  final int index;
  final List<MusicalNote> notes;
}
