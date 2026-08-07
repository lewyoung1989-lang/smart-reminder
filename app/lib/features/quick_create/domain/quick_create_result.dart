import '../../reminder_drafts/domain/reminder_draft.dart';

class QuickCreateResult {
  const QuickCreateResult({required this.sourceText, required this.draft});

  final String sourceText;
  final ReminderDraft draft;
}
