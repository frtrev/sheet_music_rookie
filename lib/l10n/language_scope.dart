import 'package:flutter/widgets.dart';

import '../models/app_language.dart';

class LanguageScope extends InheritedWidget {
  const LanguageScope({
    super.key,
    required this.language,
    required this.onChanged,
    required super.child,
  });
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  static LanguageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>();

  @override
  bool updateShouldNotify(LanguageScope oldWidget) =>
      language != oldWidget.language;
}
