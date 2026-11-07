import 'dart:async';

import 'package:flutter/material.dart';

import '../services/composition_storage_service.dart';
import '../services/score_playback_service.dart';

class SavedSheetsDialog extends StatefulWidget {
  const SavedSheetsDialog({
    super.key,
    required this.sheets,
    required this.storage,
    required this.onShare,
    this.playback,
  });

  final List<SavedComposition> sheets;
  final CompositionStorageService storage;
  final Future<void> Function(BuildContext, SavedComposition) onShare;
  final ScorePlaybackService? playback;

  @override
  State<SavedSheetsDialog> createState() => _SavedSheetsDialogState();
}

class _SavedSheetsDialogState extends State<SavedSheetsDialog>
    with WidgetsBindingObserver {
  late final List<SavedComposition> _sheets = [...widget.sheets];
  late final ScorePlaybackService _playback =
      widget.playback ?? ScorePlaybackService();
  String? _activePath;
  final Set<String> _removing = {};
  int _request = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback.onComplete = () {
      if (mounted) setState(() => _activePath = null);
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_stop());
    }
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stop() async {
    _request++;
    if (mounted) setState(() => _activePath = null);
    try {
      await _playback.stop(resetPosition: true);
    } catch (_) {
      _error('Playback could not be stopped.');
    }
  }

  Future<void> _togglePlayback(SavedComposition item) async {
    if (_closing) return;
    final wasActive = _activePath == item.path;
    final request = ++_request;
    setState(() => _activePath = wasActive ? null : item.path);
    try {
      await _playback.stop(resetPosition: true);
      if (wasActive || !mounted || request != _request) return;
      final played = await _playback.play(item.composition);
      if (!mounted || request != _request) return;
      if (!played) {
        setState(() => _activePath = null);
        _error('This sheet has no playable notes.');
      }
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _activePath = null);
      _error('The sheet could not be played.');
    }
  }

  Future<void> _close([SavedComposition? selected]) async {
    if (_closing) return;
    _closing = true;
    await _stop();
    if (mounted) Navigator.pop(context, selected);
  }

  Future<void> _remove(SavedComposition item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove sheet?'),
        content: Text(
          'Remove “${item.composition.title}” from your saved sheets?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _closing) return;
    setState(() => _removing.add(item.path));
    try {
      if (_activePath == item.path) await _stop();
      await widget.storage.removeSaved(item);
      if (mounted) {
        setState(() => _sheets.removeWhere((sheet) => sheet.path == item.path));
      }
    } catch (_) {
      _error('The sheet could not be removed.');
    } finally {
      if (mounted) setState(() => _removing.remove(item.path));
    }
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    _playback.onComplete = null;
    unawaited(_playback.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Sheets'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: _sheets.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No saved sheets yet.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _sheets.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _sheetRow(_sheets[index]),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_close()),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  Widget _sheetRow(SavedComposition item) {
    final title = item.composition.title;
    final date = item.modifiedAt.toLocal();
    final dateLabel =
        '${date.month}/${date.day}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final enabled = !_closing && !_removing.contains(item.path);
    final active = _activePath == item.path;
    return InkWell(
      key: ValueKey(item.path),
      onTap: enabled ? () => unawaited(_close(item)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.music_note, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${item.composition.keySignature.name} • $dateLabel',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _action(
              icon: active ? Icons.stop_rounded : Icons.play_arrow_rounded,
              tooltip: '${active ? 'Stop' : 'Play'} $title',
              onPressed: enabled
                  ? () => unawaited(_togglePlayback(item))
                  : null,
            ),
            Builder(
              builder: (shareContext) => _action(
                icon: Icons.ios_share_rounded,
                tooltip: 'Share $title',
                onPressed: enabled
                    ? () => unawaited(widget.onShare(shareContext, item))
                    : null,
              ),
            ),
            _action(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Remove $title',
              onPressed: enabled ? () => unawaited(_remove(item)) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) => IconButton(
    icon: Icon(icon, size: 22),
    tooltip: tooltip,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 44, height: 48),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}
