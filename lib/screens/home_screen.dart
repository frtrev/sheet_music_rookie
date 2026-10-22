import 'package:flutter/material.dart';

import '../models/composition.dart';
import 'score_editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 58,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Sheet Music Rookie',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sing it. See it. Shape it.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 48),
                  FilledButton.icon(
                    onPressed: () => _chooseClef(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Opening saved compositions is coming in a future phase.',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    icon: const Icon(Icons.tune),
                    label: const Text('Settings'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.all(18),
                    ),
                  ),
                  const SizedBox(height: 34),
                  const Text(
                    'Offline • No account required',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseClef(BuildContext context) async {
    final clef = await showModalBottomSheet<ClefType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose a clef',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ClefButton(
                      symbol: '𝄞',
                      label: 'Treble Clef',
                      onTap: () => Navigator.pop(context, ClefType.treble),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ClefButton(
                      symbol: '𝄢',
                      label: 'Bass Clef',
                      onTap: () => Navigator.pop(context, ClefType.bass),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (clef != null && context.mounted) {
      final octaveRange = await _chooseRange(context);
      if (octaveRange == null || !context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ScoreEditorScreen(clef: clef, octaveRange: octaveRange),
        ),
      );
    }
  }

  Future<OctaveRange?> _chooseRange(BuildContext context) {
    return showModalBottomSheet<OctaveRange>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose an octave range',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Detected notes will be written and played in this range.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                for (final range in OctaveRange.values)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        range == OctaveRange.standard
                            ? '•'
                            : range.notationLabel.replaceAll(
                                RegExp('[a-z]'),
                                '',
                              ),
                      ),
                    ),
                    title: Text(range.label),
                    subtitle: Text(_rangeDescription(range)),
                    onTap: () => Navigator.pop(context, range),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rangeDescription(OctaveRange range) => switch (range) {
    OctaveRange.twoOctavesDown => 'Write two octaves below the detected pitch',
    OctaveRange.octaveDown => 'Write one octave below the detected pitch',
    OctaveRange.standard => 'Write at the detected pitch',
    OctaveRange.octaveUp => 'Write one octave above the detected pitch',
    OctaveRange.twoOctavesUp => 'Write two octaves above the detected pitch',
  };
}

class _ClefButton extends StatelessWidget {
  const _ClefButton({
    required this.symbol,
    required this.label,
    required this.onTap,
  });
  final String symbol;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Ink(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(symbol, style: const TextStyle(fontSize: 58, height: 1)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}
