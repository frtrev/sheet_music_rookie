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
    appBar: AppBar(title: const Text('Settings')),
    body: _settings == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Sound & practice',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Personalize voice polish, practice, and recognition. Everything runs offline.',
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
