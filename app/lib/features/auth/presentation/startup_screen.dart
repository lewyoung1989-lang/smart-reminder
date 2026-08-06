import 'package:flutter/material.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({this.onRetry, super.key});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: onRetry == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 40),
                      const SizedBox(height: 16),
                      const Text('暂时无法连接服务器'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
          ),
        ),
      );
}
