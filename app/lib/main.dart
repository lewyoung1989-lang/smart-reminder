import 'dart:async';

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
import 'features/medicine_cabinet/domain/medicine_models.dart';
import 'features/medicine_ocr/data/medicine_ocr_api.dart';
import 'features/medicine_ocr/presentation/medicine_ocr_screen.dart';
import 'features/plans/data/plan_repository.dart';
import 'features/reminder_drafts/application/reminder_creation_service.dart';
import 'features/reminder_drafts/data/reminder_draft_api.dart';
import 'features/reminder_drafts/presentation/reminder_composer_screen.dart';
import 'features/reminders/data/reminder_api.dart';
import 'features/reminders/presentation/reminder_home_screen.dart';
import 'features/today/data/today_repository.dart';
import 'features/voice_input/data/audio_recorder_gateway.dart';
import 'features/voice_input/data/voice_transcription_api.dart';
import 'features/voice_input/services/voice_input_service.dart';
import 'features/voice_input/services/voice_input_service_controller.dart';
import 'platform/notifications/local_notification_scheduler.dart';
import 'platform/notifications/reminder_notification_scheduler.dart';
import 'platform/permissions/camera_permission_gateway.dart';

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
    this.authController,
    this.cameraPermissionGateway,
    super.key,
  });

  final AppConfig config;
  final ReminderNotificationScheduler notificationScheduler;
  final TokenStore? tokenStore;
  final AuthController? authController;
  final CameraPermissionGateway? cameraPermissionGateway;

  @override
  State<SmartReminderApp> createState() => _SmartReminderAppState();
}

class _SmartReminderAppState extends State<SmartReminderApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ReminderDraftApi _reminderDraftApi;
  late final ReminderApi _reminderApi;
  late final ReminderCreationService _reminderCreationService;
  late final MedicineCabinetApi _medicineCabinetApi;
  late final ApiMedicineRepository _medicineRepository;
  late final MedicineOcrApi _medicineOcrApi;
  late final TokenStore _tokenStore;
  late final AuthApi _refreshApi;
  late final AuthenticatedClient _authenticatedClient;
  late final AuthApi _authApi;
  late final AuthController _authController;
  late final bool _ownsAuthController;
  late final CameraPermissionGateway _cameraPermissionGateway;
  var _cameraPermissionState = CameraPermissionState.unavailable;
  var _themeMode = ThemeMode.system;
  late final VoiceTranscriptionApi _voiceApi;
  late final VoiceInputService _voiceInput;
  late final VoiceInputServiceController _voiceInputController;

  @override
  void initState() {
    super.initState();
    _tokenStore =
        widget.tokenStore ?? SecureTokenStore(FlutterSecureKeyValueStore());
    _cameraPermissionGateway = widget.cameraPermissionGateway ??
        PermissionHandlerCameraPermissionGateway();
    WidgetsBinding.instance.addObserver(this);
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
    _ownsAuthController = widget.authController == null;
    _authController = widget.authController ??
        AuthController(
          tokenStore: _tokenStore,
          gateway: _authApi,
        );
    _authController.addListener(_authChanged);
    _authenticatedClient.onSessionExpired = _authController.expireSession;
    _reminderDraftApi = ReminderDraftApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _reminderCreationService = ReminderCreationService(
      confirmDraft: _reminderDraftApi.confirmDraft,
      notificationScheduler: widget.notificationScheduler,
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
    _voiceApi = VoiceTranscriptionApi(
      baseUrl: widget.config.apiBaseUrl,
      client: _authenticatedClient,
    );
    _voiceInput = VoiceInputService(
      recorder: RecordAudioRecorderGateway(),
      transcribe: _voiceApi.transcribe,
    );
    _voiceInputController = VoiceInputServiceController(
      startRecording: _voiceInput.start,
      stopAndTranscribe: _voiceInput.stopAndTranscribe,
      cancelRecording: _voiceInput.cancel,
    );
    if (_ownsAuthController) _authController.restore();
    unawaited(_refreshCameraPermission());
  }

  void _authChanged() {
    if (_authController.status != AuthStatus.authenticated) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCameraPermission());
    }
  }

  Future<void> _refreshCameraPermission() async {
    final state = await _cameraPermissionGateway.current();
    if (mounted) setState(() => _cameraPermissionState = state);
  }

  void _updateCameraPermission(CameraPermissionState state) {
    if (mounted) setState(() => _cameraPermissionState = state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceInputController.dispose();
    unawaited(_voiceInput.dispose());
    _voiceApi.close();
    _reminderDraftApi.close();
    _reminderApi.close();
    _medicineCabinetApi.close();
    _medicineOcrApi.close();
    _authController.removeListener(_authChanged);
    if (_ownsAuthController) _authController.dispose();
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
    var permission = await _cameraPermissionGateway.current();
    if (!mounted) return false;
    _updateCameraPermission(permission);
    if (permission == CameraPermissionState.permanentlyDenied ||
        permission == CameraPermissionState.unavailable) {
      return false;
    }
    if (permission == CameraPermissionState.denied) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return false;
      final accepted = await showDialog<bool>(
        context: navigator.context,
        builder: (context) => AlertDialog(
          title: const Text('允许使用相机？'),
          content: const Text('用于拍摄药盒和有效期。识别结果需要你确认后才会加入药箱。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('暂不允许'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (accepted != true) return false;
      permission = await _cameraPermissionGateway.request();
      _updateCameraPermission(permission);
      if (permission != CameraPermissionState.ready) return false;
    }
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

  void _openCameraSettings() {
    unawaited(_cameraPermissionGateway.openSystemSettings());
  }

  MedicineCaptureAvailability get _medicineCaptureAvailability =>
      switch (_cameraPermissionState) {
        CameraPermissionState.ready => MedicineCaptureAvailability.ready,
        CameraPermissionState.denied => MedicineCaptureAvailability.denied,
        CameraPermissionState.permanentlyDenied =>
          MedicineCaptureAvailability.permanentlyDenied,
        CameraPermissionState.unavailable =>
          MedicineCaptureAvailability.unavailable,
      };

  Future<void> _openReminderManager() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => ReminderHomeScreen(
          listReminders: ({required status, pageUrl}) =>
              _reminderApi.list(status: status, pageUrl: pageUrl),
          cancelReminder: _reminderApi.cancel,
          notificationScheduler: widget.notificationScheduler,
          createReminder: (_) => ReminderComposerScreen(
            createDraft: _reminderDraftApi.createDraft,
            confirmDraft: _reminderDraftApi.confirmDraft,
            voiceInputController: _voiceInputController,
            notificationScheduler: widget.notificationScheduler,
          ),
        ),
      ),
    );
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
      home: KeyedSubtree(
        key: ValueKey(_authController.status),
        child: _home(),
      ),
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
            onOpenReminderManager: _openReminderManager,
            createDraft: _reminderDraftApi.createDraft,
            reminderCreationService: _reminderCreationService,
            voiceInputController: _voiceInputController,
            onDeleteBatch: (batch) => _medicineCabinetApi.deleteBatch(batch.id),
            onCaptureMedicine: _openMedicineOcr,
            captureAvailability: _medicineCaptureAvailability,
            onOpenSystemSettings: _openCameraSettings,
          ),
      };
}
