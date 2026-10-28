import 'package:flutter/material.dart';

import '../models/phrase_draft.dart';

class PhraseReviewPanel extends StatelessWidget {
  const PhraseReviewPanel({
    super.key,
    required this.draft,
    required this.onAccept,
    required this.onDiscard,
    required this.onFinish,
  });
  final PhraseDraft draft;
  final VoidCallback onAccept;
  final VoidCallback onDiscard;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (draft.stage) {
              PhraseStage.recording => 'Listening to your phrase…',
              PhraseStage.analyzing => 'Analyzing your phrase…',
              PhraseStage.review => 'Write this phrase to the score?',
              PhraseStage.failed => draft.message ?? 'No clear notes found.',
            }, textAlign: TextAlign.center),
            if (draft.stage == PhraseStage.recording)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Pause to review, or tap Review now. Up to 30 seconds per phrase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (draft.stage == PhraseStage.review)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Grey notes are a preview. Recording waits for your choice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (draft.stage == PhraseStage.analyzing)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: onDiscard,
                  icon: const Icon(Icons.close),
                  label: Text(
                    draft.stage == PhraseStage.review ? 'No' : 'Discard',
                  ),
                ),
                if (draft.stage == PhraseStage.review)
                  FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                    label: const Text('Yes'),
                  ),
                if (draft.stage == PhraseStage.recording)
                  FilledButton(
                    onPressed: onFinish,
                    child: const Text('Review now'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
