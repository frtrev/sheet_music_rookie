import '../l10n/l10n.dart';

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
              PhraseStage.recording => context.l10n.listeningToYourPhrase,
              PhraseStage.analyzing => context.l10n.analyzingYourPhrase,
              PhraseStage.review => context.l10n.writeThisPhraseToTheScore,
              PhraseStage.failed => context.l10n.label(
                draft.message ?? context.l10n.noClearNotesFound,
              ),
            }, textAlign: TextAlign.center),
            if (draft.stage == PhraseStage.recording)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  context
                      .l10n
                      .pauseToReviewOrTapReviewNowUpTo30SecondsPerPhrase,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (draft.stage == PhraseStage.review)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  context.l10n.greyNotesAreAPreviewRecordingWaitsForYourChoice,
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
                    draft.stage == PhraseStage.review
                        ? context.l10n.no
                        : context.l10n.discard,
                  ),
                ),
                if (draft.stage == PhraseStage.review)
                  FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                    label: Text(context.l10n.yes),
                  ),
                if (draft.stage == PhraseStage.recording)
                  FilledButton(
                    onPressed: onFinish,
                    child: Text(context.l10n.reviewNow),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
