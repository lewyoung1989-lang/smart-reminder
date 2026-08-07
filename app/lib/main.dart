import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'config/app_config.dart';
import 'core/network/authenticated_client.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_api.dart';
import 'features/auth/data/secure_token_store.dart';
import 'features/auth/data/token_store.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/startup_screen.dart';
import 'features/home/presentation/app_shell.dart';
import 'features/medicine_cabinet/data/api_medicine_repository.dart';
import 'features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'features/medicine_cabinet/domain/medicine_models.dart';
import 'features/medicine_cabinet/presentation/medicine_cabinet_screen.dart';
import 'features/medicine_ocr/data/medicine_ocr_api.dart';
import 'features/medicine_ocr/presentation/medicine_ocr_screen.dart';
import 'features/reminder_drafts/data/reminder_draft_api.dart';
import 'features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'features/reminders/data/reminder_api.dart';
import 'features/reminders/presentation/reminder_home_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
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
    this.tokenStore,
    super.key,
  });

  final AppConfig config;
  final ReminderNotificationScheduler notificationScheduler;
  final TokenStore? tokenStore;

  @override
  State<SmartReminderApp> createState() => _SmartReminderAppState();
}

class _SmartReminderAppState extends State<SmartReminderApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ReminderDraftApi _reminderDraftApi;
  late final ReminderApi _reminderApi;
  late final MedicineCabinetApi _medicineCabinetApi;
  late final ApiMedicineRepository _medicineRepository;
  late final MedicineOcrApi _medicineOcrApi;
  late final TokenStore _tokenStore;
  late final AuthApi _refreshApi;
  late final AuthenticatedClient _authenticatedClient;
  late final AuthApi _authApi;
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _tokenStore =
        widget.tokenStore ?? SecureTokenStore(FlutterSecureKeyValueStore());
    _refreshApi = AuthApi(
      baseUrl: widget.config.apiBaseUrl,
      client: http.Client(),
    );
    _authenticatedClient = AuthenticatedClient(
      apiBaseUri: Uri.parse(widget.config.apiBaseUrl),
      inner: http.Client(),
      tokenStore: _tokenStore,
      refreshTokens: _refreshApi.refresh,
    );
    _authApi = AuthApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _authController = AuthController(
      tokenStore: _tokenStore,
      gateway: _authApi,
    )..addListener(_authChanged);
    _authenticatedClient.onSessionExpired = _authController.expireSession;
    _reminderDraftApi = ReminderDraftApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _reminderApi = ReminderApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _medicineCabinetApi = MedicineCabinetApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _medicineRepository = ApiMedicineRepository(_medicineCabinetApi);
    _medicineOcrApi = MedicineOcrApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _authController.restore();
  }

  void _authChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _reminderDraftApi.close();
    _reminderApi.close();
    _medicineCabinetApi.close();
    _medicineOcrApi.close();
    _authController
      ..removeListener(_authChanged)
      ..dispose();
    _authApi.close();
    _refreshApi.close();
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

  Future<bool> _openMedicineOcr() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    return (await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => MedicineOcrScreen(
              capture: _captureMedicineImage,
              createJob: _medicineOcrApi.createJob,
              getJob: _medicineOcrApi.getJob,
              confirmJob: _medicineOcrApi.confirmJob,
            ),
          ),
        )) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
      home: _home(),
    );
  }

  Widget _home() => switch (_authController.status) {
        AuthStatus.booting => const StartupScreen(),
        AuthStatus.connectionError => StartupScreen(
            onRetry: _authController.restore,
          ),
        AuthStatus.unauthenticated => AuthScreen(
            onLogin: (phone, password) => _authController.login(
              phone: phone,
              password: password,
            ),
            onRegister: (phone, password, passwordConfirm) =>
                _authController.register(
              phone: phone,
              password: password,
              passwordConfirm: passwordConfirm,
            ),
          ),
        AuthStatus.authenticated => AppShell(
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
              repository: _medicineRepository,
              onDeleteBatch: (batch) =>
                  _medicineCabinetApi.deleteBatch(batch.id),
              captureAvailability: MedicineCaptureAvailability.ready,
              onCapture: _openMedicineOcr,
            ),
            profile: ProfileScreen(
              user: _authController.user!,
              onChangePassword: (current, password, confirm) =>
                  _authController.changePassword(
                currentPassword: current,
                newPassword: password,
                newPasswordConfirm: confirm,
              ),
              onLogout: _authController.logout,
            ),
          ),
      };
}
