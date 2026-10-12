import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_property_row.dart';
import '../../../ui/components/app_status_banner.dart';
import '../domain/plan_models.dart';

import 'edit_medication_plan_sheet.dart';

class PlanDetailScreen extends StatefulWidget {
  const PlanDetailScreen({
    required this.detail,
    this.onPause,
    this.onResume,
    this.onEdit,
    this.onDelete,
    this.onUpdateMedication,
    super.key,
  });

  final PlanDetail detail;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onResume;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  final Future<PlanDetail> Function({
    required String medicineName,
    required String doseText,
    required List<String> times,
  })? onUpdateMedication;

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  late PlanDetail _detail = widget.detail;

  @override
  void didUpdateWidget(covariant PlanDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail != widget.detail) {
      _detail = widget.detail;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _detail.summary;
    final action = summary.status == PlanStatus.paused ? widget.onResume : widget.onPause;
    final actionLabel = summary.status == PlanStatus.paused ? '恢复计划' : '暂停计划';
    final sourceText = _detail.sourceText.trim();
    final canEdit = (widget.onUpdateMedication != null &&
            _detail.summary.kind == PlanKind.medication) ||
        widget.onEdit != null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppPageHeader(
                leading: Navigator.canPop(context)
                    ? IconButton(
                        tooltip: '返回计划',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(LucideIcons.arrowLeft),
                      )
                    : null,
                eyebrow: _kindLabel(summary.kind),
                title: summary.title,
                actions: <Widget>[
                  PopupMenuButton<_MoreAction>(
                    tooltip: '更多操作',
                    icon: const Icon(LucideIcons.ellipsis),
                    onSelected: (value) => _handleMoreAction(context, value),
                    itemBuilder: (context) => <PopupMenuEntry<_MoreAction>>[
                      _menuItem(
                        value: _MoreAction.edit,
                        label: '编辑计划',
                        enabled: canEdit,
                      ),
                      _menuItem(
                        value: _MoreAction.delete,
                        label: '删除计划',
                        enabled: widget.onDelete != null,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _StatusSummary(summary: summary),
              if (_detail.isDegraded) ...[
                const SizedBox(height: AppSpacing.lg),
                AppStatusBanner(
                  severity: AppStatusSeverity.warning,
                  title: '计划已降级执行',
                  message: _detail.degradationMessage ?? '已使用可用信息继续提醒',
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              _DetailSection(
                title: '计划信息',
                children: <Widget>[
                  AppPropertyRow(
                    label: '下次执行',
                    value: Text(_formatDateTime(summary.nextRunAt)),
                  ),
                  AppPropertyRow(
                      label: '提醒方式', value: Text(_detail.reminderLabel)),
                  if (_detail.doseLabel != null && _detail.doseLabel!.isNotEmpty)
                    AppPropertyRow(
                      label: '单次剂量',
                      value: Text(_detail.doseLabel!),
                    ),
                  if (_detail.arrivalLabel != null)
                    AppPropertyRow(
                        label: '到达时间', value: Text(_detail.arrivalLabel!)),
                  if (_detail.destination != null)
                    AppPropertyRow(
                        label: '目的地', value: Text(_detail.destination!)),
                  if (_detail.queriedSources.isNotEmpty)
                    AppPropertyRow(
                      label: '查询来源',
                      value: Text(_detail.queriedSources.join('、')),
                    ),
                  if (sourceText.isNotEmpty)
                    AppPropertyRow(
                      label: '原始备注',
                      value: SelectableText(sourceText),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _DetailSection(
                title: '执行记录',
                children: _detail.executions.isEmpty
                    ? <Widget>[const Text('暂无执行记录')]
                    : <Widget>[
                        for (final execution in _detail.executions)
                          _ExecutionRow(execution: execution),
                      ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              _ActionButton(
                label: actionLabel,
                onPressed:
                    action == null ? null : () => _runAction(context, action),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_MoreAction> _menuItem({
    required _MoreAction value,
    required String label,
    required bool enabled,
  }) {
    return PopupMenuItem<_MoreAction>(
      value: value,
      enabled: enabled,
      child: Semantics(
        label: enabled ? label : '$label，服务尚未接入',
        child: Text(label),
      ),
    );
  }

  Future<void> _handleMoreAction(
      BuildContext context, _MoreAction action) async {
    switch (action) {
      case _MoreAction.edit:
        if (_detail.summary.kind == PlanKind.medication &&
            widget.onUpdateMedication != null) {
          await EditMedicationPlanSheet.show(
            context,
            detail: _detail,
            onSave: ({
              required String medicineName,
              required String doseText,
              required List<String> times,
            }) async {
              final newDetail = await widget.onUpdateMedication!(
                medicineName: medicineName,
                doseText: doseText,
                times: times,
              );
              if (mounted) {
                setState(() => _detail = newDetail);
              }
            },
          );
        } else {
          widget.onEdit?.call();
        }
      case _MoreAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除这个计划？'),
            content: const Text('删除后无法恢复。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && widget.onDelete != null) {
          if (!context.mounted) return;
          await _runAction(context, widget.onDelete!);
        }
    }
  }

  static Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败，请稍后重试')),
      );
    }
  }
}

enum _MoreAction { edit, delete }

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, this.onPressed});

  final String label;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed == null ? null : () => onPressed!(),
      child: Text(label),
    );
    if (onPressed != null) return button;
    return Semantics(
      button: true,
      enabled: false,
      label: '$label，服务尚未接入',
      child: ExcludeSemantics(child: button),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.summary});

  final PlanSummary summary;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final color = switch (summary.status) {
      PlanStatus.active => semantic.success,
      PlanStatus.pending => semantic.warning,
      PlanStatus.paused => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Semantics(
      label: '状态：${_statusLabel(summary.status)}',
      child: Row(
        children: <Widget>[
          Icon(LucideIcons.circleCheck, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text('状态：${_statusLabel(summary.status)}'),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < children.length; index += 1) ...[
          children[index],
          if (index < children.length - 1) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ],
    );
  }
}

class _ExecutionRow extends StatelessWidget {
  const _ExecutionRow({required this.execution});

  final PlanExecution execution;

  @override
  Widget build(BuildContext context) {
    final statusText = _executionLabel(execution);
    final redundant = execution.message.trim().isEmpty ||
        execution.message.trim() == '等待执行' ||
        execution.message.trim() == statusText;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$statusText · ${_formatDateTime(execution.startedAt)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (!redundant) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(execution.message),
          ],
        ],
      ),
    );
  }
}

String _statusLabel(PlanStatus status) => switch (status) {
      PlanStatus.active => '运行中',
      PlanStatus.pending => '待确认',
      PlanStatus.paused => '已暂停',
    };

String _kindLabel(PlanKind kind) => switch (kind) {
      PlanKind.medication => '用药计划',
      PlanKind.departure => '出行计划',
      PlanKind.reminder => '提醒计划',
    };

String _executionLabel(PlanExecution execution) {
  if (execution.status == PlanExecutionStatus.pending) {
    if (execution.startedAt.isBefore(DateTime.now())) {
      return '未触发';
    }
    return '待执行';
  }
  return switch (execution.status) {
    PlanExecutionStatus.pending => '待执行',
    PlanExecutionStatus.running => '执行中',
    PlanExecutionStatus.completed => '已完成',
    PlanExecutionStatus.degraded => '已降级',
    PlanExecutionStatus.failed => '失败',
    PlanExecutionStatus.cancelled => '已取消',
  };
}

String _formatDateTime(DateTime value) {
  return '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
