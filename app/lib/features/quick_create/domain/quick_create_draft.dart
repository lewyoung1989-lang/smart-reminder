import '../../reminder_drafts/domain/reminder_draft.dart';

/// 快速创建接口返回的统一草稿。
///
/// `draft_type=reminder` 时携带一次性提醒草稿；
/// `draft_type=workflow` 时携带工作流草稿（周期用药、有效期、智能出门）。
class QuickCreateDraft {
  const QuickCreateDraft.reminder({required ReminderDraft reminder})
      : kind = QuickCreateDraftKind.reminder,
        _reminder = reminder,
        _workflow = null;

  const QuickCreateDraft.workflow({required WorkflowDraft workflow})
      : kind = QuickCreateDraftKind.workflow,
        _reminder = null,
        _workflow = workflow;

  factory QuickCreateDraft.fromJson(Map<String, dynamic> json) {
    final draftType = json['draft_type'] as String? ?? 'reminder';
    if (draftType == 'workflow') {
      return QuickCreateDraft.workflow(
        workflow: WorkflowDraft.fromJson(json),
      );
    }
    return QuickCreateDraft.reminder(
      reminder: ReminderDraft.fromJson(json),
    );
  }

  final QuickCreateDraftKind kind;
  final ReminderDraft? _reminder;
  final WorkflowDraft? _workflow;

  ReminderDraft? get reminder => _reminder;

  WorkflowDraft? get workflow => _workflow;

  bool get isWorkflow => kind == QuickCreateDraftKind.workflow;
}

enum QuickCreateDraftKind { reminder, workflow }

/// 工作流草稿（对应后端 WorkflowDraft 响应）。
class WorkflowDraft {
  const WorkflowDraft({
    required this.id,
    required this.title,
    required this.templateHint,
    required this.slots,
    required this.ambiguities,
    required this.policyDecision,
    required this.riskLevel,
    required this.policyQuestion,
  });

  factory WorkflowDraft.fromJson(Map<String, dynamic> json) {
    final task = json['task'] as Map<String, dynamic>? ?? const {};
    final policy = json['policy'] as Map<String, dynamic>? ?? const {};
    final slots = task['slots'] as Map<String, dynamic>? ?? const {};
    return WorkflowDraft(
      id: json['id'] as String,
      title: task['title'] as String? ?? '提醒草稿',
      templateHint: task['template_hint'] as String?,
      slots: Map<String, Object?>.from(slots),
      ambiguities: List<String>.from(task['ambiguities'] as List? ?? const []),
      policyDecision: policy['decision'] as String? ?? 'needs_clarification',
      riskLevel: policy['risk_level'] as String? ?? 'R2',
      policyQuestion: policy['question'] as String?,
    );
  }

  final String id;
  final String title;
  final String? templateHint;
  final Map<String, Object?> slots;
  final List<String> ambiguities;
  final String policyDecision;
  final String riskLevel;
  final String? policyQuestion;

  bool get needsClarification =>
      policyDecision == 'needs_clarification' || ambiguities.isNotEmpty;

  bool get canConfirm => !needsClarification && policyDecision != 'blocked';

  String get templateLabel => switch (templateHint) {
        'medication_cycle' => '周期用药',
        'medicine_expiry' => '药品有效期',
        'smart_departure' => '智能出门',
        _ => '生活工作流',
      };

  String get frequencyLabel => switch (slots['frequency']) {
        'daily' => '每天',
        'weekly' => '每周',
        _ => '周期待补充',
      };

  String? get timeOfDay => slots['time_of_day'] as String?;

  List<String> get times {
    final values = slots['times'];
    if (values is List) {
      final parsed = values.whereType<String>().toList(growable: false);
      if (parsed.isNotEmpty) return parsed;
    }
    final legacy = timeOfDay;
    return legacy == null ? const [] : [legacy];
  }

  String? get timeLabel => times.isEmpty ? null : times.join('、');

  String? get medicineName {
    final value = slots['medicine_name'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  String? get doseText {
    final value = slots['dose_text'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  /// 追问或歧义文案，用于确认页展示。
  String get clarificationMessage {
    final messages = <String>[
      ...ambiguities,
      if (ambiguities.isEmpty && policyQuestion != null) policyQuestion!,
    ];
    return messages.isEmpty ? '需要补充信息' : messages.join('，');
  }
}
