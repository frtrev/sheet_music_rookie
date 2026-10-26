# Playback sound options

The app currently generates WAV audio offline with four modeled instruments: piano, nylon guitar, flute, and organ. The instrument selection is stored with the score and exported as a General MIDI program. Playback, note previews, and melody-test reference audio use the selected voice. These are synthesis models, not recordings of real acoustic instruments.

The piano now uses independently decaying, band-limited partials instead of the previous static detuned harmonics. Listening on real devices is still required to judge the improvement.

## Sample-based upgrade candidates

- **GeneralUser GS + FluidSynth:** a practical candidate for many instrument choices. GeneralUser GS's author describes 261 presets and 13 drum kits with a 30.7 MB RAM footprint. It relies on standards-compliant SoundFont modulation. FluidSynth implements SoundFont 2 rendering; integrating a mobile renderer, packaging the bank, and measuring render time/memory would be separate implementation work. Sources: https://github.com/mrbumpy409/GeneralUser-GS and https://www.fluidsynth.org/api/Introduction.html
- **Salamander Grand Piano:** a sampled piano with 16 velocity layers, release noises, and resonance recordings under CC BY 3.0. The maintained SFZ mapping uses SFZ 2/ARIA extensions, so a compatible sampler or a carefully tested subset/conversion is needed. Source: https://github.com/sfzinstruments/SalamanderGrandPiano

Recommendation for the next sound-engine iteration: prototype GeneralUser GS with a compatible offline renderer on iOS and Android, compare piano/guitar/flute samples against the modeled voices, and measure startup latency, peak memory, app size, and rendering time on long repeated scores. For a piano-only premium-quality sound, evaluate a compact sample set derived from Salamander separately. No external sound banks or native rendering dependencies have been bundled in this change.
