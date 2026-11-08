import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../l10n/language_scope.dart';
import '../models/app_language.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = LanguageScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<AppLanguage>(
            key: ValueKey('app-language-${scope.language.name}'),
            initialValue: scope.language,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.l10n.language),
            items: [
              DropdownMenuItem(
                value: AppLanguage.system,
                child: Text(context.l10n.deviceLanguage),
              ),
              DropdownMenuItem(
                value: AppLanguage.english,
                child: Text(context.l10n.english),
              ),
              DropdownMenuItem(
                value: AppLanguage.spanish,
                child: Text(context.l10n.spanish),
              ),
            ],
            onChanged: (language) {
              if (language != null) scope.onChanged(language);
            },
          ),
          const SizedBox(height: 8),
          Text(context.l10n.languageHelp),
        ],
      ),
    );
  }
}
