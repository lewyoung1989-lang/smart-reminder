import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/auth/domain/auth_models.dart';
import '../../features/family/data/family_api.dart';
import '../../features/family/presentation/family_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../theme/app_spacing.dart';
import '../../ui/components/app_page_header.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.user,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onChangePassword,
    required this.onLogout,
    this.familyApi,
    this.onFamilyMembershipChanged,
    super.key,
  });

  final AuthUser user;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function(
    String currentPassword,
    String newPassword,
    String newPasswordConfirm,
  ) onChangePassword;
  final Future<void> Function() onLogout;
  final FamilyApi? familyApi;
  final ValueChanged<bool>? onFamilyMembershipChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _selectedThemeMode;
  var _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.themeMode;
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) {
      _selectedThemeMode = widget.themeMode;
    }
  }

  void _selectThemeMode(ThemeMode themeMode) {
    setState(() => _selectedThemeMode = themeMode);
    widget.onThemeModeChanged(themeMode);
  }

  Future<void> _openPasswordChange() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(onSubmit: widget.onChangePassword),
      ),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已更新')),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前设备？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loggingOut = true);
    try {
      await widget.onLogout();
    } catch (_) {
      // The controller still clears local session state when logout is offline.
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xxl,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            children: [
              AppPageHeader(
                title: '设置',
                actions: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.arrowLeft),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              _SettingsSection(
                title: '账户',
                children: [
                  ListTile(
                    leading: const Icon(LucideIcons.user),
                    title: Text(widget.user.phoneMasked),
                    subtitle: Text(
                      widget.user.phoneVerified ? '手机号已验证' : '手机号未验证',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.keyRound),
                    title: const Text('修改密码'),
                    trailing: const Icon(LucideIcons.chevronRight, size: 20),
                    onTap: _openPasswordChange,
                  ),
                  ListTile(
                    leading: const Icon(LucideIcons.users),
                    title: const Text('我的家庭'),
                    subtitle: const Text('管理共享药箱与家庭成员'),
                    trailing: const Icon(LucideIcons.chevronRight, size: 20),
                    enabled: widget.familyApi != null,
                    onTap: widget.familyApi == null
                        ? null
                        : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => FamilyScreen(
                                  api: widget.familyApi!,
                                  onMembershipChanged:
                                      widget.onFamilyMembershipChanged,
                                ),
                              ),
                            ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              _SettingsSection(
                title: '外观',
                children: [
                  RadioGroup<ThemeMode>(
                    groupValue: _selectedThemeMode,
                    onChanged: (value) {
                      if (value != null) _selectThemeMode(value);
                    },
                    child: const Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.system,
                          title: Text('跟随系统'),
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.light,
                          title: Text('浅色'),
                        ),
                        RadioListTile<ThemeMode>(
                          value: ThemeMode.dark,
                          title: Text('深色'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              TextButton.icon(
                onPressed: _loggingOut ? null : _confirmLogout,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(LucideIcons.logOut),
                label: Text(_loggingOut ? '正在退出' : '退出登录'),
              ),
            ],
          ),
        ),
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Text(title, style: theme.textTheme.labelMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        Material(
          color: theme.colorScheme.surface,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index += 1) ...[
                children[index],
                if (index < children.length - 1)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
