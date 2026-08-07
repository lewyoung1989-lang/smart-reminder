import 'package:flutter/material.dart';

import '../../reminder_drafts/domain/reminder_draft.dart';
import '../../reminder_drafts/presentation/reminder_draft_screen.dart';

class VoiceDraftScreen extends StatelessWidget {
  const VoiceDraftScreen({
    required this.transcript,
    required this.draft,
    required this.onConfirm,
    this.onEdit,
    this.now,
    super.key,
  });

  final String transcript;
  final ReminderDraft draft;
  final Future<void> Function() onConfirm;
  final VoidCallback? onEdit;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ReminderDraftScreen(
      sourceText: transcript,
      draft: draft,
      onConfirm: onConfirm,
      onEdit: onEdit ?? () => Navigator.maybePop(context),
      now: now,
    );
  }
}
