import 'package:flutter/material.dart';

import '../domain/reminder_draft.dart';


class VoiceDraftScreen extends StatefulWidget {
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
  State<VoiceDraftScreen> createState() => _VoiceDraftScreenState();
}


class _VoiceDraftScreenState extends State<VoiceDraftScreen> {
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
      appBar: AppBar(title: const Text('语音创建提醒')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('识别内容', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(widget.transcript),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('结构化提醒草稿', style: theme.textTheme.titleMedium),
              ),
              const Chip(label: Text('待确认')),
            ],
          ),
          _DraftRow(label: '提醒', value: draft.title),
          _DraftRow(label: '时间', value: draft.displayTime(now)),
          _DraftRow(
            label: '强度',
            value: draft.severity == ReminderSeverity.alarm ? '闹钟' : '通知',
          ),
          if (draft.weatherMessage != null)
            _DraftRow(label: '天气条件', value: draft.weatherMessage!),
          if (draft.ambiguities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              draft.ambiguities.join('，'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改草稿'),
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
