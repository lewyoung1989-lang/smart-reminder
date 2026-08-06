import 'package:flutter/material.dart';

import '../../auth/domain/auth_models.dart';
import 'change_password_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.user,
    required this.onChangePassword,
    required this.onLogout,
    super.key,
  });

  final AuthUser user;
  final Future<void> Function(
    String currentPassword,
    String newPassword,
    String newPasswordConfirm,
  ) onChangePassword;
  final Future<void> Function() onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loggingOut = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(widget.user.phoneMasked),
                subtitle: Row(
                  children: [
                    Icon(
                      widget.user.phoneVerified
                          ? Icons.verified_outlined
                          : Icons.info_outline,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.user.phoneVerified ? '手机号已验证' : '手机号未验证',
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('修改密码'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openPasswordChange,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: _loggingOut ? null : _confirmLogout,
                  icon: const Icon(Icons.logout),
                  label: Text(_loggingOut ? '正在退出' : '退出登录'),
                ),
              ),
            ],
          ),
        ),
      );

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
      // AuthController clears the local session even if the server is offline.
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }
}
