import '../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_theme.dart';
import '../models/composition.dart';
import '../services/composition_storage_service.dart';
import '../widgets/saved_sheets_dialog.dart';
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
                          if (context.l10n.localeName == 'es') ...[
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.welcomeSpanish,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.singItSeeItShapeIt,
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
                                  context.l10n.yourVoiceYourMusic,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  context
                                      .l10n
                                      .turnAMelodyIntoSheetMusicOneNoteAtATime,
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
                                    label: Text(context.l10n.create),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _openSaved(context),
                            icon: const Icon(Icons.folder_open_rounded),
                            label: Text(context.l10n.sheets),
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
                            label: Text(context.l10n.settings),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            context.l10n.offlineNoAccountRequired,
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
                  context.l10n.chooseAClef,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 18),
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: 12),
                  Row(
                    children: [
                      for (var column = 0; column < 2; column++) ...[
                        if (column > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _ClefButton(
                            symbol: ClefType.values[row * 2 + column].symbol,
                            label: context.l10n.clefName(
                              context.l10n.label(
                                ClefType.values[row * 2 + column].label,
                              ),
                            ),
                            onTap: () => Navigator.pop(
                              context,
                              ClefType.values[row * 2 + column],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
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
          SnackBar(content: Text(context.l10n.savedSheetsCouldNotBeRead)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final selected = await showDialog<SavedComposition>(
      context: context,
      builder: (_) => SavedSheetsDialog(
        sheets: saved,
        storage: service,
        onShare: _shareSaved,
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
          SnackBar(content: Text(context.l10n.theSheetCouldNotBeShared)),
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
                  context.l10n.chooseAnOctaveRange,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.detectedNotesWillBeWrittenAndPlayedInThisRange,
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
                    title: Text(context.l10n.label(range.label)),
                    subtitle: Text(_rangeDescription(context, range)),
                    onTap: () => Navigator.pop(context, range),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rangeDescription(
    BuildContext context,
    OctaveRange range,
  ) => switch (range) {
    OctaveRange.twoOctavesDown =>
      context.l10n.writeTwoOctavesBelowTheDetectedPitch,
    OctaveRange.octaveDown => context.l10n.writeOneOctaveBelowTheDetectedPitch,
    OctaveRange.standard => context.l10n.writeAtTheDetectedPitch,
    OctaveRange.octaveUp => context.l10n.writeOneOctaveAboveTheDetectedPitch,
    OctaveRange.twoOctavesUp =>
      context.l10n.writeTwoOctavesAboveTheDetectedPitch,
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
          Text(symbol, style: const TextStyle(fontSize: 48, height: 1.8)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}
