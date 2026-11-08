import '../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single-line field positioned over the actual lyric row on the score.
class InlineLyricEditor extends StatelessWidget {
  const InlineLyricEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.line,
    required this.onMoveLine,
    required this.onDone,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String line;
  final ValueChanged<int> onMoveLine;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => onMoveLine(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => onMoveLine(1),
      const SingleActivator(LogicalKeyboardKey.escape): onCancel,
    },
    child: TextFieldTapRegion(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('inline-lyric-text'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.l10n.lyricLine(line),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 7,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => onDone(),
                onTapOutside: (_) => onDone(),
              ),
            ),
            _arrow(
              Icons.arrow_upward,
              context.l10n.previousLyricLine,
              () => onMoveLine(-1),
            ),
            _arrow(
              Icons.arrow_downward,
              context.l10n.nextLyricLine,
              () => onMoveLine(1),
            ),
            _arrow(Icons.check, context.l10n.finishLyricEditing, onDone),
          ],
        ),
      ),
    ),
  );

  Widget _arrow(IconData icon, String tooltip, VoidCallback action) =>
      ExcludeFocus(
        child: IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tooltip,
          onPressed: action,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 34),
        ),
      );
}
