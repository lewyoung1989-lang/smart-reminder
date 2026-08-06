import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/authenticated_client.dart';
import '../data/auth_api.dart';
import '../data/token_store.dart';
import '../domain/auth_models.dart';

enum AuthStatus { booting, unauthenticated, authenticated, connectionError }

class AuthController extends ChangeNotifier {
  AuthController({required TokenStore tokenStore, required AuthGateway gateway})
      : _tokenStore = tokenStore,
        _gateway = gateway;

  final TokenStore _tokenStore;
  final AuthGateway _gateway;

  AuthStatus _status = AuthStatus.booting;
  AuthUser? _user;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  void expireSession() {
    _user = null;
    _setStatus(AuthStatus.unauthenticated);
  }

  Future<void> restore() async {
    _setStatus(AuthStatus.booting);
    try {
      final tokens = await _tokenStore.read();
      if (tokens == null) {
        _user = null;
        _setStatus(AuthStatus.unauthenticated);
        return;
      }
      _user = await _gateway.me();
      _setStatus(AuthStatus.authenticated);
    } on SessionExpiredException {
      await _tokenStore.clear();
      _user = null;
      _setStatus(AuthStatus.unauthenticated);
    } on http.ClientException {
      _setStatus(AuthStatus.connectionError);
    } catch (_) {
      _setStatus(AuthStatus.connectionError);
    }
  }

  Future<void> login({required String phone, required String password}) async {
    final session = await _gateway.login(phone: phone, password: password);
    await _acceptSession(session);
  }

  Future<void> register({
    required String phone,
    required String password,
    required String passwordConfirm,
  }) async {
    final session = await _gateway.register(
      phone: phone,
      password: password,
      passwordConfirm: passwordConfirm,
    );
    await _acceptSession(session);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirm,
  }) async {
    final session = await _gateway.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      newPasswordConfirm: newPasswordConfirm,
    );
    await _acceptSession(session);
  }

  Future<void> logout() async {
    final tokens = await _tokenStore.read();
    try {
      if (tokens != null) {
        await _gateway.logout(tokens.refreshToken);
      }
    } finally {
      await _tokenStore.clear();
      _user = null;
      _setStatus(AuthStatus.unauthenticated);
    }
  }

  Future<void> _acceptSession(AuthSession session) async {
    await _tokenStore.write(session.tokens);
    _user = session.user;
    _setStatus(AuthStatus.authenticated);
  }

  void _setStatus(AuthStatus value) {
    _status = value;
    notifyListeners();
  }
}
