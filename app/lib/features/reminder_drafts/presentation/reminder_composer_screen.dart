import 'package:flutter/material.dart';

import '../domain/reminder_draft.dart';
import 'reminder_draft_screen.dart';


class ReminderComposerScreen extends StatefulWidget {
  const ReminderComposerScreen({
    required this.createDraft,
    required this.confirmDraft,
    this.now,
    super.key,
  });

  final Future<ReminderDraft> Function(String) createDraft;
  final Future<String> Function(String) confirmDraft;
  final DateTime? now;

  @override
  State<ReminderComposerScreen> createState() => _ReminderComposerScreenState();
}


class _ReminderComposerScreenState extends State<ReminderComposerScreen> {
  final _controller = TextEditingController();
  ReminderDraft? _draft;
  String? _sourceText;
  String? _error;
  bool _isParsing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isParsing) return;
    setState(() {
      _isParsing = true;
      _error = null;
    });
    try {
      final draft = await widget.createDraft(text);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _sourceText = text;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '暂时无法解析，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null) return;
    try {
      await widget.confirmDraft(draft.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒已创建')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败，请稍后重试')),
      );
    }
  }

  void _edit() {
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft != null) {
      return ReminderDraftScreen(
        sourceText: _sourceText ?? '',
        draft: draft,
        onConfirm: _confirm,
        onEdit: _edit,
        now: widget.now,
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('智能提醒')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _controller,
            enabled: !_isParsing,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _parse(),
            decoration: const InputDecoration(
              labelText: '提醒内容',
              hintText: '1分钟后提醒我喝水',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _isParsing ? null : _parse,
              icon: _isParsing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: const Text('解析提醒'),
            ),
          ),
        ],
      ),
    );
  }
}
