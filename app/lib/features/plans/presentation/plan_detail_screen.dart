import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../ui/components/app_confirm_dialog.dart';
import '../../../ui/components/app_page_header.dart';
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
    this.onTakeMedication,
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
  final Future<PlanDetail?> Function(String occurrenceId)? onTakeMedication;

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  late PlanDetail _detail = widget.detail;
  bool _isTakingMedication = false;
  bool _isTogglingStatus = false;

  @override
  void didUpdateWidget(covariant PlanDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail != widget.detail) {
      _detail = widget.detail;
    }
  }

  Future<void> _handleTakeAdvance() async {
    final nextOcc = _detail.nextOccurrence;
    if (nextOcc == null || widget.onTakeMedication == null || _isTakingMedication) {
      return;
    }

    final confirmed = await showMedicationConfirmDialog(
      context: context,
      medicineTitle: nextOcc.medicineName ?? _detail.summary.title,
      doseLabel: nextOcc.dosageText ?? _detail.doseLabel,
      isAdvance: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isTakingMedication = true);
    try {
      final updated = await widget.onTakeMedication!(nextOcc.id);
      if (mounted) {
        if (updated != null) {
          setState(() => _detail = updated);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已成功记录提前服药，库存已更新留痕'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打卡失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTakingMedication = false);
      }
    }
  }

  Future<void> _togglePlanStatus() async {
    if (_isTogglingStatus) return;
    final isPaused = _detail.summary.status == PlanStatus.paused;
    final action = isPaused ? widget.onResume : widget.onPause;
    if (action == null) return;

    if (!isPaused) {
      final confirmed = await showAppConfirmDialog(
        context: context,
        icon: LucideIcons.pauseCircle,
        iconColor: const Color(0xFFD97706),
        iconBackgroundColor: const Color(0xFFFEF3C7),
        title: '确认暂停用药计划',
        primaryText: _detail.summary.title,
        secondaryText: _detail.doseLabel != null && _detail.doseLabel!.isNotEmpty
            ? '计划剂量：${_detail.doseLabel}'
            : null,
        infoBannerText: '暂停后系统将停止推送此计划的用药提醒通知，直到您手动恢复。',
        confirmLabel: '确认暂停',
        cancelLabel: '取消',
        confirmColor: const Color(0xFFD97706),
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _isTogglingStatus = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isPaused ? '计划已恢复执行' : '计划已暂停提醒')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTogglingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _detail.summary;
    final isPaused = summary.status == PlanStatus.paused;
    final sourceText = _detail.sourceText.trim();
    final canEdit = (widget.onUpdateMedication != null &&
            _detail.summary.kind == PlanKind.medication) ||
        widget.onEdit != null;

    final hasNextOccurrence = _detail.nextOccurrence != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
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
                        value: _MoreAction.togglePause,
                        label: isPaused ? '恢复计划' : '暂停计划',
                        enabled: (isPaused ? widget.onResume : widget.onPause) != null,
                      ),
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
              const SizedBox(height: AppSpacing.lg),

              // 核心卡片：状态、下一次时间与快速双操作区
              _buildMainControlCard(context, summary, isPaused, hasNextOccurrence),

              if (_detail.isDegraded) ...[
                const SizedBox(height: AppSpacing.md),
                AppStatusBanner(
                  severity: AppStatusSeverity.warning,
                  title: '计划已降级执行',
                  message: _detail.degradationMessage ?? '已使用可用信息继续提醒',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // 执行记录 · 留痕卡片
              _buildExecutionSection(context),

              const SizedBox(height: AppSpacing.lg),

              // 计划规则信息卡片
              _buildPlanInfoCard(context, summary, sourceText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainControlCard(
    BuildContext context,
    PlanSummary summary,
    bool isPaused,
    bool hasNextOccurrence,
  ) {
    final nextOcc = _detail.nextOccurrence;
    final scheduledText = nextOcc != null
        ? _formatDateTime(nextOcc.scheduledAt)
        : _formatDateTime(summary.nextRunAt);
    final doseText = nextOcc?.dosageText ?? _detail.doseLabel ?? '';
    final toggleAction = isPaused ? widget.onResume : widget.onPause;
    final toggleActionLabel = isPaused ? '恢复计划' : '暂停计划';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Text(
                  _kindLabel(summary.kind),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaused ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isPaused ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      isPaused ? LucideIcons.pause : LucideIcons.circleCheck,
                      size: 13,
                      color: isPaused ? const Color(0xFFB45309) : const Color(0xFF059669),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(summary.status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isPaused ? const Color(0xFFB45309) : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_detail.medicationConfig?.medicineName.isNotEmpty == true &&
              _detail.medicationConfig?.medicineName != summary.title) ...[
            Text(
              _detail.medicationConfig!.medicineName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // 下次计划提醒横幅
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isPaused ? const Color(0xFFF8FAFC) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isPaused ? const Color(0xFFE2E8F0) : const Color(0xFFBBF7D0),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  isPaused ? LucideIcons.bellOff : LucideIcons.clock,
                  size: 18,
                  color: isPaused ? const Color(0xFF94A3B8) : const Color(0xFF059669),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isPaused ? '计划已暂停' : '下次计划服药',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPaused ? const Color(0xFF64748B) : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPaused
                            ? '已暂停日常推送提醒，点击下方可随时恢复'
                            : '$scheduledText${doseText.isNotEmpty ? " · $doseText" : ""}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isPaused ? const Color(0xFF475569) : const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 核心操作双按钮：提前服用打卡 & 暂停/恢复计划
          Row(
            children: <Widget>[
              if (!isPaused && hasNextOccurrence) ...[
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: _isTakingMedication ? null : _handleTakeAdvance,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isTakingMedication
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.pill, size: 18),
                    label: Text(
                      _isTakingMedication ? '正在打卡...' : '提前服用打卡',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                flex: 2,
                child: toggleAction != null
                    ? OutlinedButton.icon(
                        onPressed: _isTogglingStatus ? null : _togglePlanStatus,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isPaused ? const Color(0xFF059669) : const Color(0xFF475569),
                          backgroundColor: isPaused ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                          side: BorderSide(
                            color: isPaused ? const Color(0xFFA7F3D0) : const Color(0xFFCBD5E1),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(
                          isPaused ? LucideIcons.play : LucideIcons.pause,
                          size: 16,
                        ),
                        label: Text(
                          toggleActionLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      )
                    : Semantics(
                        button: true,
                        enabled: false,
                        label: '$toggleActionLabel，服务尚未接入',
                        child: ExcludeSemantics(
                          child: OutlinedButton.icon(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF94A3B8),
                              backgroundColor: const Color(0xFFF8FAFC),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: Icon(
                              isPaused ? LucideIcons.play : LucideIcons.pause,
                              size: 16,
                            ),
                            label: Text(
                              toggleActionLabel,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionSection(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(LucideIcons.history, size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '执行记录 · 留痕',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '共 ${_detail.executions.length} 条',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '精确记录每次实际点击服药的时间戳与提前/推迟偏差',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_detail.executions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无执行记录',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                ),
              ),
            )
          else
            Column(
              children: <Widget>[
                for (var i = 0; i < _detail.executions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _buildExecutionCard(_detail.executions[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildExecutionCard(PlanExecution execution) {
    final statusText = _executionLabel(execution);
    final isCompleted = execution.status == PlanExecutionStatus.completed;
    final hasActualRecord = execution.message.contains('实际服药') || execution.actualTakenAt != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Icon(
                      isCompleted ? LucideIcons.circleCheck : LucideIcons.clock,
                      size: 15,
                      color: isCompleted ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_formatDateTime(execution.startedAt)} 计划',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isCompleted ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isCompleted ? const Color(0xFF166534) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          if (hasActualRecord) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(LucideIcons.checkCircle2, size: 14, color: Color(0xFF059669)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      execution.message.isNotEmpty
                          ? execution.message
                          : (execution.actualTakenAt != null
                              ? '实际服药：${_formatDateTime(execution.actualTakenAt!)}'
                              : '已按时服药'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (execution.message.isNotEmpty && execution.message != statusText) ...[
            const SizedBox(height: 6),
            Text(
              execution.message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanInfoCard(
    BuildContext context,
    PlanSummary summary,
    String sourceText,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(LucideIcons.info, size: 18, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text(
                '计划规则',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _infoRow('提醒方式', _detail.reminderLabel),
          if (_detail.medicationConfig?.times.isNotEmpty == true) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _infoRow('每日服药时间', _detail.medicationConfig!.times.join('、')),
          ],
          if (_detail.doseLabel?.isNotEmpty == true) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _infoRow('单次剂量', _detail.doseLabel!),
          ],
          if (_detail.arrivalLabel != null) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _infoRow('到达时间', _detail.arrivalLabel!),
          ],
          if (_detail.destination != null) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _infoRow('目的地', _detail.destination!),
          ],
          if (_detail.queriedSources.isNotEmpty) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _infoRow('查询来源', _detail.queriedSources.join('、')),
          ],
          if (sourceText.isNotEmpty) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            _infoRow('原始备注', sourceText),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 70, maxWidth: 110),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
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

  Future<void> _handleMoreAction(BuildContext context, _MoreAction action) async {
    switch (action) {
      case _MoreAction.togglePause:
        await _togglePlanStatus();
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
          try {
            await widget.onDelete!();
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('操作失败，请稍后重试')),
            );
          }
        }
    }
  }
}

enum _MoreAction { togglePause, edit, delete }

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
