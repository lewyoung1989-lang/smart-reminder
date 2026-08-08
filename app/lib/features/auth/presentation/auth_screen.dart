import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/auth_api.dart';

enum _AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.onLogin,
    required this.onRegister,
    super.key,
  });

  final Future<void> Function(String phone, String password) onLogin;
  final Future<void> Function(
    String phone,
    String password,
    String passwordConfirm,
  ) onRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '13800138000');
  final _passwordController = TextEditingController(text: 'Test-pass-2026');
  final _confirmController = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _submitting = false;
  int _retrySeconds = 0;
  Timer? _retryTimer;
  String? _pageError;
  final _fieldErrors = <String, String>{};

  @override
  void dispose() {
    _retryTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.alarm, size: 42),
                      const SizedBox(height: 16),
                      Text(
                        '智能提醒',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 28),
                      SegmentedButton<_AuthMode>(
                        segments: const [
                          ButtonSegment(
                            value: _AuthMode.login,
                            label: Text('登录'),
                          ),
                          ButtonSegment(
                            value: _AuthMode.register,
                            label: Text('注册'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _submitting
                            ? null
                            : (selection) => setState(() {
                                  _mode = selection.single;
                                  _pageError = null;
                                  _fieldErrors.clear();
                                  _formKey.currentState?.reset();
                                }),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('phone-field'),
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: const InputDecoration(
                          labelText: '手机号',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        onChanged: (_) => _clearFieldError('phone'),
                        validator: (value) =>
                            _fieldErrors['phone'] ??
                            (RegExp(r'^1[3-9]\d{9}$').hasMatch(value ?? '')
                                ? null
                                : '请输入正确的 11 位手机号'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('password-field'),
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) => _clearFieldError('password'),
                        validator: (value) =>
                            _fieldErrors['password'] ??
                            (value != null &&
                                    value.length >= 8 &&
                                    value.length <= 64
                                ? null
                                : '密码长度需为 8 至 64 位'),
                      ),
                      if (_mode == _AuthMode.register) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('password-confirm-field'),
                          controller: _confirmController,
                          obscureText: !_confirmVisible,
                          decoration: InputDecoration(
                            labelText: '确认密码',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _confirmVisible ? '隐藏密码' : '显示密码',
                              onPressed: () => setState(
                                () => _confirmVisible = !_confirmVisible,
                              ),
                              icon: Icon(
                                _confirmVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          onChanged: (_) =>
                              _clearFieldError('password_confirm'),
                          validator: (value) =>
                              _fieldErrors['password_confirm'] ??
                              (value == _passwordController.text
                                  ? null
                                  : '两次输入的密码不一致'),
                        ),
                      ],
                      if (_pageError != null || _retrySeconds > 0) ...[
                        const SizedBox(height: 16),
                        Text(
                          _retrySeconds > 0
                              ? '操作过于频繁，请 $_retrySeconds 秒后重试'
                              : _pageError!,
                          key: const Key('auth-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('auth-submit'),
                        onPressed:
                            _submitting || _retrySeconds > 0 ? null : _submit,
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_mode == _AuthMode.login ? '登录' : '注册'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _submit() async {
    setState(() {
      _pageError = null;
      _fieldErrors.clear();
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_mode == _AuthMode.login) {
        await widget.onLogin(
          _phoneController.text,
          _passwordController.text,
        );
      } else {
        await widget.onRegister(
          _phoneController.text,
          _passwordController.text,
          _confirmController.text,
        );
      }
    } on AuthApiException catch (error) {
      if (mounted) _handleApiError(error);
    } on http.ClientException {
      if (mounted) setState(() => _pageError = '无法连接服务器，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleApiError(AuthApiException error) {
    if (error.code == 'rate_limited') {
      _startRetryCountdown(error.retryAfter ?? 1);
      return;
    }
    final message = _messageFor(error);
    if (const {'phone', 'password', 'password_confirm'}.contains(error.field)) {
      setState(() => _fieldErrors[error.field!] = message);
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _pageError = message);
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() => _fieldErrors.remove(field));
  }

  void _startRetryCountdown(int retryAfter) {
    _retryTimer?.cancel();
    setState(() => _retrySeconds = retryAfter < 1 ? 1 : retryAfter);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _retrySeconds -= 1;
        if (_retrySeconds <= 0) {
          _retrySeconds = 0;
          timer.cancel();
          _retryTimer = null;
        }
      });
    });
  }

  static String _messageFor(AuthApiException error) => switch (error.code) {
        'phone_already_registered' => '该手机号已注册，请直接登录',
        'invalid_credentials' => '手机号或密码错误',
        'invalid_phone' => '请输入正确的 11 位手机号',
        'weak_password' => '密码强度不足，请更换后重试',
        'password_mismatch' => '两次输入的密码不一致',
        'rate_limited' => '操作过于频繁，请稍后重试',
        _ => '操作失败，请稍后重试',
      };
}
