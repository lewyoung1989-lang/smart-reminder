import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_spacing.dart';
import '../domain/reminder_draft.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_property_row.dart';
import '../../../ui/components/app_status_banner.dart';

class ReminderDraftScreen extends StatefulWidget {
  const ReminderDraftScreen({
    required this.sourceText,
    required this.draft,
    required this.onConfirm,
    required this.onReparse,
    this.now,
    super.key,
  });

  final String sourceText;
  final ReminderDraft draft;
  final Future<void> Function() onConfirm;
  final Future<void> Function(String text) onReparse;
  final DateTime? now;

  @override
  State<ReminderDraftScreen> createState() => _ReminderDraftScreenState();
}

class _ReminderDraftScreenState extends State<ReminderDraftScreen> {
  late String _sourceText = widget.sourceText;
  late final TextEditingController _editController =
      TextEditingController(text: widget.sourceText);
  bool _isConfirming = false;
  bool _isEditing = false;
  bool _isReparsing = false;

  @override
  void didUpdateWidget(covariant ReminderDraftScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceText != widget.sourceText) {
      _sourceText = widget.sourceText;
      _editController.text = widget.sourceText;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) setState(() => _isConfirming = false);
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
    final draft = widget.draft;
    final now = widget.now ?? DateTime.now();
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
              eyebrow: '提醒草稿',
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
              title: draft.canConfirm ? '请确认提醒内容' : '请补充提醒信息',
              message: draft.canConfirm ? '请检查时间和提醒内容后确认创建' : '补充信息后再确认创建',
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_isEditing) ...[
              TextField(
                key: const Key('reminder-reparse-input'),
                controller: _editController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '原始表达',
                  hintText: '修改描述后重新解析',
                ),
              ),
            ] else ...[
              AppPropertyRow(label: '原始表达', value: Text(_sourceText)),
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(label: '提醒', value: Text(draft.title)),
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(
                label: '时间',
                value: Text(draft.displayTime(now)),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(
                label: '强度',
                value: Text(
                  draft.severity == ReminderSeverity.alarm ? '闹钟' : '通知',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPropertyRow(
                label: '解析方式',
                value: Text(draft.parserSourceLabel),
              ),
              if (draft.weatherMessage != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppPropertyRow(
                  label: '天气条件',
                  value: Text(draft.weatherMessage!),
                ),
              ],
              if (draft.ambiguities.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                AppStatusBanner(
                  severity: AppStatusSeverity.warning,
                  title: '需要补充信息',
                  message: draft.ambiguities.join('，'),
                ),
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
                        key: const Key('reminder-reparse-cancel'),
                        onPressed: _isReparsing ? null : _cancelEditing,
                        icon: const Icon(LucideIcons.x),
                        label: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('reminder-reparse-submit'),
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
                        onPressed: draft.canConfirm && !_isConfirming
                            ? _confirm
                            : null,
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
