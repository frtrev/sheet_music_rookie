/// Built-in modeled voices, with their corresponding General MIDI programs.
enum PlaybackInstrument {
  piano('Piano', 1),
  nylonGuitar('Nylon guitar', 25),
  flute('Flute', 74),
  organ('Organ', 20);

  const PlaybackInstrument(this.label, this.midiProgram);
  final String label;
  final int midiProgram;
}
