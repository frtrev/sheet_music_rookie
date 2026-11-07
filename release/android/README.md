# Android build status

No uploadable AAB is included because this project has no release keystore/signing properties configured. The normal AAB build was attempted and failed explicitly instead of using the debug key.

The final production release code and manifest compile successfully. See ../reports/android-release-compile.log and ../reports/native-artifact-audit.json. Configure the app's registered upload key in ignored android/key.properties, then run `flutter build appbundle --release` or `./scripts/prepare_store_release.sh` from the project root. Upload only the correctly signed AAB that matches the Play app's registered upload certificate.
