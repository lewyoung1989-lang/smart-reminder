import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';

class TestApp extends StatelessWidget {
  const TestApp({
    required this.home,
    this.themeMode = ThemeMode.light,
    this.textScaler = TextScaler.noScaling,
    super.key,
  });

  final Widget home;
  final ThemeMode themeMode;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: home,
    );
  }
}

extension TestAppPump on WidgetTester {
  Future<void> pumpApp(
    Widget child, {
    ThemeMode themeMode = ThemeMode.light,
    Size surfaceSize = const Size(800, 600),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    view.devicePixelRatio = 1;
    view.physicalSize = surfaceSize;
    addTearDown(view.resetDevicePixelRatio);
    addTearDown(view.resetPhysicalSize);

    await pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: surfaceSize, textScaler: textScaler),
        child: TestApp(
          themeMode: themeMode,
          textScaler: textScaler,
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child],
            ),
          ),
        ),
      ),
    );
  }
}
