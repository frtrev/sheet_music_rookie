# Store visual QA

Contact sheets are in contact-sheets/ and are QA previews only, not store uploads. Upload the full-resolution PNGs in store_assets/ instead.

Inspected all six views for iPhone medium/large, iPad 13-inch, Android phone, and Android ~7/~10-inch layouts. Confirmed actual application identity, staff/notes, clef choices, octave controls, tempo dialog, and note-insertion controls. No fake listening state or microphone data was injected. Screenshots show the app's normal scrollable editor viewport and use a deterministic original local C-major exercise.

Rejected blank iOS texture snapshots, unrelated-app permission dialogs, the Android clef-glyph overlap, and an initial phone home capture taken before icon decoding completed. Native framebuffer capture, dedicated simulators, corrected glyph spacing, and explicit asset precaching resolve those issues. Refreshed captures replace the rejected files. Tempo captures have the keyboard hidden; no system permission dialog is part of the accepted set.

No screenshot is resized, stretched, or cropped in normalization. The native source dimensions must exactly match the configured final output or normalization fails. RGB conversion removes alpha only. Dimension/count/format/size/CRC/uniqueness reports are separate from this visual inspection.
