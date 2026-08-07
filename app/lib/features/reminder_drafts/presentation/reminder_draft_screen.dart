import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/reminder_draft.dart';
import '../../../ui/components/app_page_header.dart';
import '../../../ui/components/app_property_row.dart';
import '../../../ui/components/app_status_banner.dart';

class ReminderDraftScreen extends StatefulWidget {
  const ReminderDraftScreen({
    required this.sourceText,
    required this.draft,
    required this.onConfirm,
    required this.onEdit,
    this.now,
    super.key,
  });

  final String sourceText;
  final ReminderDraft draft;
  final Future<void> Function() onConfirm;
  final VoidCallback onEdit;
  final DateTime? now;

  @override
  State<ReminderDraftScreen> createState() => _ReminderDraftScreenState();
}

class _ReminderDraftScreenState extends State<ReminderDraftScreen> {
  bool _isConfirming = false;

  Future<void> _confirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppPageHeader(
            eyebrow: '提醒草稿',
            title: '确认计划',
            actions: [
              IconButton(
                tooltip: '返回修改',
                onPressed: _isConfirming ? null : widget.onEdit,
                icon: const Icon(LucideIcons.arrowLeft),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppStatusBanner(
            severity: draft.canConfirm
                ? AppStatusSeverity.info
                : AppStatusSeverity.warning,
            title: draft.canConfirm ? '请确认提醒内容' : '请补充提醒信息',
            message: draft.canConfirm ? '请检查时间和提醒内容后确认创建' : '补充信息后再确认创建',
          ),
          const SizedBox(height: 20),
          AppPropertyRow(label: '原始表达', value: Text(widget.sourceText)),
          const SizedBox(height: 16),
          AppPropertyRow(label: '提醒', value: Text(draft.title)),
          const SizedBox(height: 16),
          AppPropertyRow(label: '时间', value: Text(draft.displayTime(now))),
          const SizedBox(height: 16),
          AppPropertyRow(
            label: '强度',
            value: Text(draft.severity == ReminderSeverity.alarm ? '闹钟' : '通知'),
          ),
          const SizedBox(height: 16),
          AppPropertyRow(label: '解析方式', value: Text(draft.parserSourceLabel)),
          if (draft.weatherMessage != null) ...[
            const SizedBox(height: 16),
            AppPropertyRow(label: '天气条件', value: Text(draft.weatherMessage!)),
          ],
          if (draft.ambiguities.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppStatusBanner(
              severity: AppStatusSeverity.warning,
              title: '需要补充信息',
              message: draft.ambiguities.join('，'),
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isConfirming ? null : widget.onEdit,
                  icon: const Icon(LucideIcons.pencil),
                  label: const Text('修改'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      draft.canConfirm && !_isConfirming ? _confirm : null,
                  icon: _isConfirming
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.check),
                  label: const Text('确认'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
