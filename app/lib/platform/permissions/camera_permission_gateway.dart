import 'package:permission_handler/permission_handler.dart';

enum CameraPermissionState { ready, denied, permanentlyDenied, unavailable }

abstract interface class CameraPermissionGateway {
  Future<CameraPermissionState> current();

  Future<CameraPermissionState> request();

  Future<bool> openSystemSettings();
}

class PermissionHandlerCameraPermissionGateway
    implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> current() async =>
      _map(await Permission.camera.status);

  @override
  Future<CameraPermissionState> request() async =>
      _map(await Permission.camera.request());

  @override
  Future<bool> openSystemSettings() => openAppSettings();

  CameraPermissionState _map(PermissionStatus value) {
    if (value.isGranted || value.isLimited) return CameraPermissionState.ready;
    if (value.isPermanentlyDenied) {
      return CameraPermissionState.permanentlyDenied;
    }
    if (value.isDenied) return CameraPermissionState.denied;
    return CameraPermissionState.unavailable;
  }
}
