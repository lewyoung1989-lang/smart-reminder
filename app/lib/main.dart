import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'app/shell/app_shell.dart';
import 'app/theme/app_theme.dart';
import 'config/app_config.dart';
import 'core/network/authenticated_client.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_api.dart';
import 'features/auth/data/secure_token_store.dart';
import 'features/auth/data/token_store.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/startup_screen.dart';
import 'features/medicine_cabinet/data/api_medicine_repository.dart';
import 'features/medicine_cabinet/data/medicine_cabinet_api.dart';
import 'features/medicine_ocr/data/medicine_ocr_api.dart';
import 'features/medicine_ocr/presentation/medicine_ocr_screen.dart';
import 'features/plans/data/plan_repository.dart';
import 'features/reminder_drafts/application/reminder_creation_service.dart';
import 'features/reminder_drafts/data/reminder_draft_api.dart';
import 'features/today/data/today_repository.dart';
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
  late final ReminderCreationService _reminderCreationService;
  late final MedicineCabinetApi _medicineCabinetApi;
  late final ApiMedicineRepository _medicineRepository;
  late final MedicineOcrApi _medicineOcrApi;
  late final TokenStore _tokenStore;
  late final AuthApi _refreshApi;
  late final AuthenticatedClient _authenticatedClient;
  late final AuthApi _authApi;
  late final AuthController _authController;
  var _themeMode = ThemeMode.system;

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
    _reminderCreationService = ReminderCreationService(
      confirmDraft: _reminderDraftApi.confirmDraft,
      notificationScheduler: widget.notificationScheduler,
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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
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
            todayRepository: const UnavailableTodayRepository(),
            planRepository: const UnavailablePlanRepository(),
            medicineRepository: _medicineRepository,
            user: _authController.user!,
            themeMode: _themeMode,
            onThemeModeChanged: (themeMode) {
              setState(() => _themeMode = themeMode);
            },
            onChangePassword: (current, password, confirm) =>
                _authController.changePassword(
              currentPassword: current,
              newPassword: password,
              newPasswordConfirm: confirm,
            ),
            onLogout: _authController.logout,
            createDraft: _reminderDraftApi.createDraft,
            reminderCreationService: _reminderCreationService,
            onDeleteBatch: (batch) => _medicineCabinetApi.deleteBatch(batch.id),
            onCaptureMedicine: _openMedicineOcr,
          ),
      };
}
