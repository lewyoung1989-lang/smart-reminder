import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../ui/components/app_content_state.dart';
import '../../../ui/components/app_page_header.dart';
import '../data/family_api.dart';
import '../domain/family_models.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({required this.api, super.key});
  final FamilyApi api;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  FamilyInfo? _family;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final family = await widget.api.getCurrent();
      if (mounted) setState(() => _family = family);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createOrJoin(bool join) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FamilyEntryDialog(join: join),
    );
    if (result == null) return;
    try {
      final family = join
          ? await widget.api.join(code: result[0], nickname: result[1])
          : await widget.api.create(name: result[0], nickname: result[1]);
      if (mounted) setState(() => _family = family);
    } catch (_) {
      _message(join ? '加入失败，请检查邀请码' : '创建家庭失败');
    }
  }

  Future<void> _invite() async {
    try {
      final invitation = await widget.api.invite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('家庭邀请码'),
          content: SelectableText(
            '${invitation.code}\n\n24 小时内有效，使用一次后失效',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成')),
          ],
        ),
      );
    } catch (_) {
      _message('邀请码创建失败');
    }
  }

  Future<void> _leaveOrDisband() async {
    final family = _family!;
    final disband = family.isAdmin;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(disband ? '解散家庭' : '退出家庭'),
        content: Text(
            disband ? '仅剩你一人时可解散。家庭库存、照片和记录将永久删除。' : '引用家庭药品的个人用药计划将自动暂停。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(disband ? '确认解散' : '确认退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (disband) {
        await widget.api.disband();
      } else {
        await widget.api.leave();
      }
      if (mounted) setState(() => _family = null);
    } catch (_) {
      _message(disband ? '家庭内还有其他成员，请先转让管理员' : '退出家庭失败');
    }
  }

  Future<void> _memberAction(FamilyMember member, bool transfer) async {
    try {
      if (transfer) {
        _family = await widget.api.transferAdmin(member.id);
      } else {
        await widget.api.removeMember(member.id);
        await _load();
      }
      if (mounted) setState(() {});
    } catch (_) {
      _message('操作失败，请稍后重试');
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              AppPageHeader(
                title: '我的家庭',
                actions: [
                  IconButton(
                      tooltip: '返回设置',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.arrowLeft))
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_loading)
                const AppContentState.loading()
              else if (_error != null)
                AppContentState.error(
                    title: '家庭信息加载失败',
                    message: '请检查网络后重试',
                    actionLabel: '重试',
                    onAction: _load)
              else if (_family == null)
                _emptyContent()
              else
                _familyContent(_family!),
            ],
          ),
        ),
      );

  Widget _emptyContent() => Column(
        children: [
          const AppContentState.empty(
              title: '还没有加入家庭', message: '创建家庭或使用 6 位邀请码加入'),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
              onPressed: () => _createOrJoin(false),
              icon: const Icon(LucideIcons.housePlus),
              label: const Text('创建家庭')),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
              onPressed: () => _createOrJoin(true),
              icon: const Icon(LucideIcons.userPlus),
              label: const Text('输入邀请码')),
        ],
      );

  Widget _familyContent(FamilyInfo family) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(family.name, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('${family.members.length}/10 位成员',
              style: Theme.of(context).textTheme.bodyMedium),
          if (family.isAdmin) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
                onPressed: _invite,
                icon: const Icon(LucideIcons.userPlus),
                label: const Text('邀请成员')),
          ],
          const SizedBox(height: AppSpacing.xl),
          Text('家庭成员', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final member in family.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  CircleAvatar(child: Text(member.nickname.characters.first)),
              title: Text(member.nickname),
              subtitle: Text(
                  '${member.phoneMasked} · ${member.role == 'admin' ? '管理员' : '成员'}'),
              trailing: family.isAdmin && !member.isSelf
                  ? PopupMenuButton<String>(
                      tooltip: '管理${member.nickname}',
                      onSelected: (value) =>
                          _memberAction(member, value == 'transfer'),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'transfer', child: Text('转让管理员')),
                        PopupMenuItem(value: 'remove', child: Text('移出家庭')),
                      ],
                    )
                  : null,
            ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: _leaveOrDisband,
            icon:
                Icon(family.isAdmin ? LucideIcons.trash2 : LucideIcons.logOut),
            label: Text(family.isAdmin ? '解散家庭' : '退出家庭'),
          ),
        ],
      );
}

class _FamilyEntryDialog extends StatefulWidget {
  const _FamilyEntryDialog({required this.join});
  final bool join;
  @override
  State<_FamilyEntryDialog> createState() => _FamilyEntryDialogState();
}

class _FamilyEntryDialogState extends State<_FamilyEntryDialog> {
  final first = TextEditingController();
  final nickname = TextEditingController();
  @override
  void dispose() {
    first.dispose();
    nickname.dispose();
    super.dispose();
  }

  void submit() {
    final value = first.text.trim();
    final nick = nickname.text.trim();
    if (value.isEmpty ||
        nick.isEmpty ||
        (widget.join && !RegExp(r'^\d{6}$').hasMatch(value))) {
      return;
    }
    Navigator.pop(context, [value, nick]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.join ? '加入家庭' : '创建家庭'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: first,
              keyboardType:
                  widget.join ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                  labelText: widget.join ? '6 位邀请码' : '家庭名称',
                  hintText: widget.join ? null : '我的家庭')),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: nickname,
              decoration: const InputDecoration(labelText: '家庭内昵称')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: submit, child: Text(widget.join ? '加入' : '创建'))
        ],
      );
}
