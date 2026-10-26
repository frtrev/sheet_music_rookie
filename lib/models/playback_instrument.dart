/// Curated General MIDI bank-zero programs from GeneralUser GS.
/// Program numbers are one-based, as required by MusicXML.
enum PlaybackInstrument {
  piano('Piano', 1, 'Keyboards'),
  brightPiano('Bright piano', 2, 'Keyboards'),
  electricPiano('Electric piano', 5, 'Keyboards'),
  harpsichord('Harpsichord', 7, 'Keyboards'),
  drawbarOrgan('Drawbar organ', 17, 'Keyboards'),
  organ('Church organ', 20, 'Keyboards'),
  reedOrgan('Reed organ', 21, 'Keyboards'),
  accordion('Accordion', 22, 'Winds'),
  harmonica('Harmonica', 23, 'Winds'),
  nylonGuitar('Nylon guitar', 25, 'Strings'),
  steelGuitar('Steel-string guitar', 26, 'Strings'),
  acousticBass('Acoustic bass', 33, 'Strings'),
  violin('Violin', 41, 'Strings'),
  viola('Viola', 42, 'Strings'),
  cello('Cello', 43, 'Strings'),
  contrabass('Contrabass', 44, 'Strings'),
  pizzicatoStrings('Pizzicato strings', 46, 'Strings'),
  harp('Harp', 47, 'Strings'),
  strings('String ensemble', 49, 'Strings'),
  trumpet('Trumpet', 57, 'Winds'),
  trombone('Trombone', 58, 'Winds'),
  tuba('Tuba', 59, 'Winds'),
  frenchHorn('French horn', 61, 'Winds'),
  sopranoSax('Soprano saxophone', 65, 'Winds'),
  altoSax('Alto saxophone', 66, 'Winds'),
  tenorSax('Tenor saxophone', 67, 'Winds'),
  baritoneSax('Baritone saxophone', 68, 'Winds'),
  oboe('Oboe', 69, 'Winds'),
  englishHorn('English horn', 70, 'Winds'),
  bassoon('Bassoon', 71, 'Winds'),
  clarinet('Clarinet', 72, 'Winds'),
  piccolo('Piccolo', 73, 'Winds'),
  flute('Flute', 74, 'Winds'),
  recorder('Recorder', 75, 'Winds'),
  panFlute('Pan flute', 76, 'Winds'),
  shakuhachi('Shakuhachi', 78, 'Winds'),
  ocarina('Ocarina', 80, 'Winds');

  const PlaybackInstrument(this.label, this.midiProgram, this.family);
  final String label;
  final int midiProgram;
  final String family;
}
