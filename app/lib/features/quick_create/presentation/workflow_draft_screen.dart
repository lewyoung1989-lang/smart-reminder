import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_property_row.dart';
import '../../../ui/components/app_status_banner.dart';
import '../domain/quick_create_draft.dart';

/// 工作流草稿确认页：展示周期用药、有效期、智能出门等计划草稿。
///
/// 草稿需要追问时，页面提供回复输入框；提交后原地刷新草稿，
/// 直到信息补齐可以确认为止。点「修改」在页面内直接编辑原始表达，
/// 重新解析后原地刷新，不再退回输入页。
class WorkflowDraftScreen extends StatefulWidget {
  const WorkflowDraftScreen({
    required this.sourceText,
    required this.draft,
    required this.onConfirm,
    required this.onReparse,
    this.onAnswer,
    super.key,
  });

  final String sourceText;
  final WorkflowDraft draft;
  final Future<void> Function(WorkflowDraft draft) onConfirm;
  final Future<void> Function(String text) onReparse;
  final Future<WorkflowDraft> Function(String answer)? onAnswer;

  @override
  State<WorkflowDraftScreen> createState() => _WorkflowDraftScreenState();
}

class _WorkflowDraftScreenState extends State<WorkflowDraftScreen> {
  late WorkflowDraft _draft = widget.draft;
  late String _sourceText = widget.sourceText;
  late final TextEditingController _answerController = TextEditingController();
  late final TextEditingController _editController =
      TextEditingController(text: widget.sourceText);
  bool _isConfirming = false;
  bool _isAnswering = false;
  bool _isEditing = false;
  bool _isReparsing = false;

  @override
  void didUpdateWidget(covariant WorkflowDraftScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      _draft = widget.draft;
    }
    if (oldWidget.sourceText != widget.sourceText) {
      _sourceText = widget.sourceText;
      _editController.text = widget.sourceText;
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    _editController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      await widget.onConfirm(_draft);
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Future<void> _submitAnswer() async {
    final onAnswer = widget.onAnswer;
    final answer = _answerController.text.trim();
    if (onAnswer == null || _isAnswering || answer.isEmpty) return;
    setState(() => _isAnswering = true);
    try {
      final updated = await onAnswer(answer);
      if (!mounted) return;
      setState(() {
        _draft = updated;
        _answerController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提交回答失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _isAnswering = false);
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editController.text = _sourceText;
    });
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

  Future<void> _reparse() async {
    final text = _editController.text.trim();
    if (_isReparsing || text.isEmpty) return;
    setState(() => _isReparsing = true);
    try {
      await widget.onReparse(text);
      // 成功时父级会替换/刷新页面；若页面仍在则恢复展示模式。
      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _sourceText = text;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法解析，请检查网络后重试')),
      );
    } finally {
      if (mounted) setState(() => _isReparsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: [
            AppPageHeader(
              eyebrow: draft.templateLabel,
              title: '确认计划',
              actions: [
                if (!_isEditing)
                  IconButton(
                    tooltip: '修改',
                    onPressed: _isConfirming ? null : _startEditing,
                    icon: const Icon(LucideIcons.pencil),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            AppStatusBanner(
              severity: draft.canConfirm
                  ? AppStatusSeverity.info
                  : AppStatusSeverity.warning,
              title: draft.canConfirm ? '请确认计划内容' : '请补充计划信息',
              message:
                  draft.canConfirm ? '请检查计划内容后确认创建' : '补充信息后再确认创建',
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_isEditing) ...[
              TextField(
                key: const Key('workflow-reparse-input'),
                controller: _editController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '原始表达',
                  hintText: '修改描述后重新解析',
                ),
              ),
            ] else ...[
              AppPropertyRow(
                label: '原始表达',
                value: Text(_sourceText),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(
                label: '计划类型',
                value: Text(draft.templateLabel),
              ),
              if (draft.medicineName != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppPropertyRow(
                  label: '药品',
                  value: Text(draft.medicineName!),
                ),
              ],
              if (draft.doseText != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppPropertyRow(label: '剂量', value: Text(draft.doseText!)),
              ],
              if (draft.templateHint == 'medication_cycle') ...[
                const SizedBox(height: AppSpacing.lg),
                AppPropertyRow(
                  label: '频率',
                  value: Text(draft.frequencyLabel),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppPropertyRow(
                  label: '时间',
                  value: Text(draft.timeOfDay ?? '待补充'),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(
                label: '风险等级',
                value:
                    Text(draft.riskLevel == 'R2' ? 'R2（每次确认）' : draft.riskLevel),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(
                label: '解析方式',
                value: const Text('本地工作流规则'),
              ),
              if (draft.needsClarification) ...[
                const SizedBox(height: AppSpacing.lg),
                AppStatusBanner(
                  severity: AppStatusSeverity.warning,
                  title: '需要补充信息',
                  message: draft.clarificationMessage,
                ),
                if (widget.onAnswer != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    key: const Key('workflow-answer-input'),
                    controller: _answerController,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: '补充信息',
                      hintText: '直接回答上面的问题，例如：吃阿莫西林1片',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('workflow-answer-submit'),
                    onPressed: _isAnswering ? null : _submitAnswer,
                    icon: _isAnswering
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.send),
                    label: const Text('提交回答'),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _isEditing
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('workflow-reparse-cancel'),
                        onPressed: _isReparsing ? null : _cancelEditing,
                        icon: const Icon(LucideIcons.x),
                        label: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('workflow-reparse-submit'),
                        onPressed: _isReparsing ? null : _reparse,
                        icon: _isReparsing
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.refreshCw),
                        label: const Text('重新解析'),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isConfirming ? null : _startEditing,
                        icon: const Icon(LucideIcons.pencil),
                        label: const Text('修改'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            draft.canConfirm && !_isConfirming ? _confirm : null,
                        icon: _isConfirming
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.check),
                        label: const Text('确认'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
