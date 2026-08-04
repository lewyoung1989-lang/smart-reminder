import 'package:flutter/material.dart';

import '../domain/reminder_draft.dart';


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
    final theme = Theme.of(context);
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回修改',
          onPressed: _isConfirming ? null : widget.onEdit,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('提醒草稿'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('原始内容', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(widget.sourceText),
          const Divider(height: 32),
          _DraftRow(label: '提醒', value: draft.title),
          _DraftRow(label: '时间', value: draft.displayTime(now)),
          _DraftRow(
            label: '强度',
            value: draft.severity == ReminderSeverity.alarm ? '闹钟' : '通知',
          ),
          _DraftRow(label: '解析方式', value: draft.parserSourceLabel),
          if (draft.weatherMessage != null)
            _DraftRow(label: '天气条件', value: draft.weatherMessage!),
          if (draft.ambiguities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    draft.ambiguities.join('，'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isConfirming ? null : widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: draft.canConfirm && !_isConfirming ? _confirm : null,
                  icon: _isConfirming
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('确认创建'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
