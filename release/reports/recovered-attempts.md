# Recovered validation failures

All attempts were inspected; failures were not counted as successful deliverables.

- Initial SDK/simulator calls were sandbox restricted. Authorized elevated host access allowed use of existing Flutter/Xcode/Android tools.
- Initial analysis caught one type error in the new integration test plus existing analyzer warnings in the app. The type error and app warnings were fixed, and analysis was rerun cleanly.
- Native integration screenshot API on iOS produced blank Metal-backed content. Those images were rejected visually. The replacement workflow captures the native simulator framebuffer through simctl, followed by exact-size RGB normalization.
- A shared pre-existing iPhone simulator had an unrelated app permission sheet above the test app. Those captures were rejected. Clean dedicated SMR Store simulators were created and captured instead.
- Capture exposed TextEditingController use after disposal during the tempo dialog's exit animation. Save and tempo dialog routes now wait for route completion before disposing their controllers. Subsequent real-device-class integration runs exercise opening/canceling the tempo dialog successfully.
- The first iPad wrapper run reached six successful native captures and a passing integration test, but its post-capture shell step was interrupted while the automation was being revised. The current script passes bash syntax validation; the completed iPad native captures were normalized and validated independently. Future full runs use the stabilized script.
- Final visual review found Android clef-font fallback metrics overlapping the Treble label. The glyph line spacing/size was corrected and the chooser screen refreshed on every device class. A new selective-capture option initially skipped a navigation-settling pump; this test-only issue was fixed before accepting the refreshed captures.
- Android AAB packaging fails intentionally when release signing properties are absent. Production release compilation and manifest merging were separately executed successfully without creating a misleading debug-signed store artifact.

Final artifact readiness is based on the current full validation report and visual review, not an earlier attempt's output.
