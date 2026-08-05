import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'config/app_config.dart';
import 'features/home/presentation/app_shell.dart';
import 'features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import 'features/medicine_ocr/data/medicine_ocr_api.dart';
import 'features/medicine_ocr/presentation/medicine_ocr_screen.dart';
import 'features/reminder_drafts/data/reminder_draft_api.dart';
import 'features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'features/reminders/data/reminder_api.dart';
import 'features/reminders/presentation/reminder_home_screen.dart';
import 'platform/notifications/local_notification_scheduler.dart';
import 'platform/notifications/reminder_notification_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationGateway = FlutterLocalNotificationGateway();
  await notificationGateway.initialize();
  runApp(
    SmartReminderApp(
      config: AppConfig.fromEnvironment(),
      notificationScheduler: LocalNotificationScheduler(
        gateway: notificationGateway,
      ),
    ),
  );
}

class SmartReminderApp extends StatefulWidget {
  const SmartReminderApp({
    required this.config,
    required this.notificationScheduler,
    super.key,
  });

  final AppConfig config;
  final ReminderNotificationScheduler notificationScheduler;

  @override
  State<SmartReminderApp> createState() => _SmartReminderAppState();
}

class _SmartReminderAppState extends State<SmartReminderApp> {
  late final ReminderDraftApi _reminderDraftApi;
  late final ReminderApi _reminderApi;
  late final MedicineCabinetApi _medicineCabinetApi;
  late final MedicineOcrApi _medicineOcrApi;

  @override
  void initState() {
    super.initState();
    _reminderDraftApi = ReminderDraftApi(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.config.apiAccessToken,
    );
    _reminderApi = ReminderApi(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.config.apiAccessToken,
    );
    _medicineCabinetApi = MedicineCabinetApi(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.config.apiAccessToken,
    );
    _medicineOcrApi = MedicineOcrApi(
      baseUrl: widget.config.apiBaseUrl,
      accessToken: widget.config.apiAccessToken,
    );
  }

  @override
  void dispose() {
    _reminderDraftApi.close();
    _reminderApi.close();
    _medicineCabinetApi.close();
    _medicineOcrApi.close();
    super.dispose();
  }

  Future<List<int>?> _captureMedicineImage(String kind) async {
    // 客户端先压缩并限制长边，降低移动网络上传耗时和云端 OCR 内存占用。
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 2048,
    );
    return image?.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能提醒',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166B5A),
          surface: const Color(0xFFF7F9F8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: AppShell(
        reminders: ReminderHomeScreen(
          listReminders: ({required status, pageUrl}) =>
              _reminderApi.list(status: status, pageUrl: pageUrl),
          cancelReminder: _reminderApi.cancel,
          notificationScheduler: widget.notificationScheduler,
          createReminder: (_) => ReminderComposerScreen(
            createDraft: _reminderDraftApi.createDraft,
            confirmDraft: _reminderDraftApi.confirmDraft,
            notificationScheduler: widget.notificationScheduler,
          ),
        ),
        medicineCabinet: MedicineCabinetScreen(
          listBatches: _medicineCabinetApi.listBatches,
        ),
        medicineOcr: MedicineOcrScreen(
          capture: _captureMedicineImage,
          createJob: _medicineOcrApi.createJob,
          getJob: _medicineOcrApi.getJob,
          confirmJob: _medicineOcrApi.confirmJob,
        ),
      ),
    );
  }
}
