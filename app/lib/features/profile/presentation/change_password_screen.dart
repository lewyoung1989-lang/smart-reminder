import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../auth/data/auth_api.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({required this.onSubmit, super.key});

  final Future<void> Function(
    String currentPassword,
    String newPassword,
    String newPasswordConfirm,
  ) onSubmit;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  bool _currentVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('修改密码')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _passwordField(
                    key: const Key('current-password-field'),
                    controller: _currentController,
                    label: '当前密码',
                    visible: _currentVisible,
                    onToggle: () => setState(
                      () => _currentVisible = !_currentVisible,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _passwordField(
                    key: const Key('new-password-field'),
                    controller: _newController,
                    label: '新密码',
                    visible: _newVisible,
                    onToggle: () => setState(() => _newVisible = !_newVisible),
                  ),
                  const SizedBox(height: 16),
                  _passwordField(
                    key: const Key('new-password-confirm-field'),
                    controller: _confirmController,
                    label: '确认新密码',
                    visible: _confirmVisible,
                    onToggle: () => setState(
                      () => _confirmVisible = !_confirmVisible,
                    ),
                    confirmation: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存新密码'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _passwordField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    bool confirmation = false,
  }) =>
      TextFormField(
        key: key,
        controller: controller,
        obscureText: !visible,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: visible ? '隐藏密码' : '显示密码',
            onPressed: onToggle,
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        validator: (value) {
          if (value == null || value.length < 8 || value.length > 64) {
            return '密码长度需为 8 至 64 位';
          }
          if (confirmation && value != _newController.text) {
            return '两次输入的密码不一致';
          }
          return null;
        },
      );

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _currentController.text,
        _newController.text,
        _confirmController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.code) {
            'current_password_invalid' => '当前密码错误',
            'invalid_current_password' => '当前密码错误',
            'weak_password' => '新密码强度不足，请更换后重试',
            'password_mismatch' => '两次输入的密码不一致',
            'rate_limited' => '操作过于频繁，请稍后重试',
            _ => '修改失败，请稍后重试',
          };
        });
      }
    } on http.ClientException {
      if (mounted) setState(() => _error = '无法连接服务器，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
