import '../../../platform/notifications/reminder_notification_scheduler.dart';
import '../domain/reminder_draft.dart';

enum CreationOutcome {
  created,
  notificationScheduled,
  notificationNotScheduled,
}

class ReminderCreationServiceResult {
  const ReminderCreationServiceResult({
    required this.reminderId,
    required this.outcome,
  });

  final String reminderId;
  final CreationOutcome outcome;
}

class ReminderNotificationSchedulingException implements Exception {
  const ReminderNotificationSchedulingException({
    required this.cause,
    required this.stackTrace,
  });

  final Object cause;
  final StackTrace stackTrace;
}

class ReminderCreationService {
  ReminderCreationService({
    required this.confirmDraft,
    this.notificationScheduler,
  });

  final Future<String> Function(String draftId) confirmDraft;
  final ReminderNotificationScheduler? notificationScheduler;
  final _statesByDraftId = <String, _DraftCreationState>{};

  Future<CreationOutcome> confirm(ReminderDraft draft) =>
      confirmWithResult(draft).then((result) => result.outcome);

  Future<ReminderCreationServiceResult> confirmWithResult(
    ReminderDraft draft,
  ) {
    final state = _statesByDraftId.putIfAbsent(
      draft.id,
      _DraftCreationState.new,
    );
    final inFlight = state.inFlight;
    if (inFlight != null) return inFlight;

    final operation = Future<ReminderCreationServiceResult>.microtask(
      () => _confirmAndSchedule(draft, state),
    );
    state.inFlight = operation;
    return operation;
  }

  Future<ReminderCreationServiceResult> _confirmAndSchedule(
    ReminderDraft draft,
    _DraftCreationState state,
  ) async {
    try {
      final existingReminderId = state.reminderId;
      final reminderId =
          existingReminderId ?? await _confirmDraft(draft, state);

      final scheduler = notificationScheduler;
      if (scheduler == null) {
        _removeState(draft.id, state);
        return ReminderCreationServiceResult(
          reminderId: reminderId,
          outcome: CreationOutcome.created,
        );
      }

      try {
        await scheduler.schedule(reminderId: reminderId, draft: draft);
      } on ReminderNotificationException {
        return ReminderCreationServiceResult(
          reminderId: reminderId,
          outcome: CreationOutcome.notificationNotScheduled,
        );
      } catch (error, stackTrace) {
        throw ReminderNotificationSchedulingException(
          cause: error,
          stackTrace: stackTrace,
        );
      }

      _removeState(draft.id, state);
      return ReminderCreationServiceResult(
        reminderId: reminderId,
        outcome: CreationOutcome.notificationScheduled,
      );
    } finally {
      state.inFlight = null;
    }
  }

  Future<String> _confirmDraft(
    ReminderDraft draft,
    _DraftCreationState state,
  ) async {
    try {
      final reminderId = await confirmDraft(draft.id);
      state.reminderId = reminderId;
      return reminderId;
    } catch (_) {
      _removeState(draft.id, state);
      rethrow;
    }
  }

  void _removeState(String draftId, _DraftCreationState state) {
    if (identical(_statesByDraftId[draftId], state)) {
      _statesByDraftId.remove(draftId);
    }
  }
}

class _DraftCreationState {
  String? reminderId;
  Future<ReminderCreationServiceResult>? inFlight;
}
