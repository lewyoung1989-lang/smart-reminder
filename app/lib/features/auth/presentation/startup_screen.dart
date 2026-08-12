import 'package:flutter/material.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({this.onRetry, super.key});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      onRetry == null
                          ? Icons.notifications_active_outlined
                          : Icons.cloud_off_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    onRetry == null ? '智能提醒启动中' : '暂时无法连接服务器',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    onRetry == null
                        ? '正在恢复登录状态和本地设置'
                        : '请确认手机与 Mac 在同一局域网，后端服务已启动',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  if (onRetry == null)
                    const CircularProgressIndicator()
                  else
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
