/// App-only language preference; system follows the device's locale changes.
enum AppLanguage {
  system('system'),
  english('en'),
  spanish('es');

  const AppLanguage(this.code);
  final String code;
}
