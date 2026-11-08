import '../l10n/l10n.dart';
import '../widgets/language_selector.dart';

import 'package:flutter/material.dart';

import '../models/voice_detection_settings.dart';
import '../services/settings_service.dart';
import '../widgets/voice_settings_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SettingsService();
  VoiceDetectionSettings? _settings;

  @override
  void initState() {
    super.initState();
    _service.load().then((value) {
      if (mounted) setState(() => _settings = value);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settings)),
    body: _settings == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const LanguageSelector(),
              Text(
                context.l10n.soundPractice,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                context
                    .l10n
                    .personalizeVoicePolishPracticeAndRecognitionEverythingRunsOffline,
              ),
              const SizedBox(height: 20),
              VoiceSettingsPanel(
                value: _settings!,
                onChanged: (value) {
                  setState(() => _settings = value);
                  _service.save(value);
                },
              ),
            ],
          ),
  );
}
