import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_theme.dart';
import '../models/composition.dart';
import '../services/composition_storage_service.dart';
import 'score_editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe1faff), AppTheme.background, Color(0xffeeecff)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.blue.withValues(alpha: .2),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: Image.asset(
                                  'assets/app_icon/app-store-1024.png',
                                  width: 112,
                                  height: 112,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Sheet Music Rookie',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sing it. See it. Shape it.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppTheme.muted,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: AppTheme.gradient,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.graphic_eq_rounded,
                                  color: AppTheme.cyan,
                                  size: 32,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Your voice. Your music.',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Turn a melody into sheet music, one note at a time.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: () => _chooseClef(context),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppTheme.blue,
                                    ),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Create'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _openSaved(context),
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Open'),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Settings'),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Offline • No account required',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
        child: SingleChildScrollView(
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

  Future<void> _openSaved(BuildContext context) async {
    final service = CompositionStorageService();
    List<SavedComposition> saved;
    try {
      saved = await service.listSaved();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved compositions could not be read.'),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (saved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved compositions yet.')),
      );
      return;
    }
    final selected = await showDialog<SavedComposition>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open composition'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: saved.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = saved[index];
              final date = item.modifiedAt.toLocal();
              final dateLabel =
                  '${date.month}/${date.day}/${date.year} '
                  '${date.hour.toString().padLeft(2, '0')}:'
                  '${date.minute.toString().padLeft(2, '0')}';
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(item.composition.title),
                subtitle: Text(
                  '${item.composition.keySignature.name} • $dateLabel',
                ),
                trailing: Builder(
                  builder: (shareContext) => IconButton(
                    onPressed: () => _shareSaved(shareContext, item),
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: 'Share ${item.composition.title}',
                  ),
                ),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScoreEditorScreen(
          clef: selected.composition.clef,
          octaveRange: selected.composition.octaveRange,
          initialComposition: selected.composition,
          initialEvents: selected.rawEvents,
          savePath: selected.path,
        ),
      ),
    );
  }

  Future<void> _shareSaved(BuildContext context, SavedComposition item) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(item.path, mimeType: 'application/vnd.recordare.musicxml'),
          ],
          title: item.composition.title,
          subject: '${item.composition.title}.mxl',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The composition could not be shared.')),
        );
      }
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
