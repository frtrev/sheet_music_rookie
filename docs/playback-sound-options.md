# Offline sampled instrument playback

GeneralUser GS v2.0.3 by S. Christian Collins is bundled at `assets/soundfonts/GeneralUser-GS.sf2` (about 31 MB). Its complete license is included alongside the bank and shown under **Playback instrument → Sound library licenses**. Source: https://github.com/mrbumpy409/GeneralUser-GS

The picker exposes 37 bank-zero General MIDI programs across Keyboards, Strings, and Winds. This includes pianos, organs, guitar, bass, bowed and plucked strings, brass, reeds, and flutes. Drum kits, percussion, synth pads/leads, sound effects and novelty presets are not offered. The complete bank remains bundled so its sample data and preset programming are unchanged.

`dart_melty_soundfont` (MIT; a Dart port of MeltySynth) renders the sampled instruments to WAV in a background isolate. The existing audio player still handles speaker/headphone output, seeking and playback-position updates. The bank asset is loaded once per app process. Each render constructs its own synthesizer, so notes/controllers from previews cannot leak into subsequent playback.

Play, note previews, and the test-result reference use this path. Selected instruments continue to round-trip through saved score metadata and MusicXML MIDI program numbers. Melody scoring and captured voice enhancement are unchanged. Legacy synchronous renderer calls without a supplied bank retain the modeled voices for headless/unit-test use; app playback explicitly requires the bundled bank.

Rendering processes note-on/off events in performance order, retains ties, adds a 350 ms release/reverb tail, and stops metronome clicks at the musical end. Sampled synthesis avoids the old static modeled timbres, but hardware listening and profiling are still needed to assess sound balance and latency on phones.

The renderer supports SoundFont envelopes, filters, LFOs and built-in reverb/chorus. It is not claimed to reproduce every GeneralUser GS modulator exactly as FluidSynth would. Upstream documentation notes that standards-compliant SoundFont modulation matters to this bank's sound: https://github.com/mrbumpy409/GeneralUser-GS/tree/main/documentation

Validation covers all 37 selected presets against the actual bank, audible nonzero PCM output, rest alignment, release-tail timing, asset loading/caching, score metadata, repeats and unchanged test scoring. Set `GENERALUSER_EXAMPLE` to a local score to run the optional complete-score rendering check.
