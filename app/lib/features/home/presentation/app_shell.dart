import 'package:flutter/material.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.reminders,
    required this.medicineCabinet,
    required this.medicineOcr,
    super.key,
  });

  final Widget reminders;
  final Widget medicineCabinet;
  final Widget medicineOcr;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            widget.reminders,
            widget.medicineCabinet,
            widget.medicineOcr,
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.alarm_outlined),
              selectedIcon: Icon(Icons.alarm),
              label: '提醒',
            ),
            NavigationDestination(
              icon: Icon(Icons.medication_outlined),
              selectedIcon: Icon(Icons.medication),
              label: '药箱',
            ),
            NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              selectedIcon: Icon(Icons.document_scanner),
              label: '拍照录入',
            ),
          ],
        ),
      );
}
