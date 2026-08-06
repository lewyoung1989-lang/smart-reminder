import 'dart:async';

import 'package:http/http.dart' as http;

import '../../features/auth/data/token_store.dart';
import '../../features/auth/domain/auth_models.dart';

typedef RefreshTokens = Future<AuthTokens> Function(String refreshToken);

class SessionExpiredException implements Exception {
  const SessionExpiredException();
}

class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({
    required this.apiBaseUri,
    required http.Client inner,
    required TokenStore tokenStore,
    required RefreshTokens refreshTokens,
    this.onSessionExpired,
  })  : _inner = inner,
        _tokenStore = tokenStore,
        _refreshTokens = refreshTokens;

  final Uri apiBaseUri;
  final http.Client _inner;
  final TokenStore _tokenStore;
  final RefreshTokens _refreshTokens;
  void Function()? onSessionExpired;
  Future<AuthTokens>? _refreshInFlight;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final snapshot = await _RequestSnapshot.capture(request);
    if (!_hasSameOrigin(snapshot.url, apiBaseUri)) {
      return _inner.send(snapshot.create());
    }

    final initialTokens = await _tokenStore.read();
    final first = await _inner.send(
      snapshot.create(accessToken: initialTokens?.accessToken),
    );
    if (first.statusCode != 401 || initialTokens == null) {
      return first;
    }
    await first.stream.drain<void>();

    final currentTokens = await _tokenStore.read();
    final refreshed = currentTokens != null &&
            currentTokens.accessToken != initialTokens.accessToken
        ? currentTokens
        : await _refresh(initialTokens);
    final retried = await _inner.send(
      snapshot.create(accessToken: refreshed.accessToken),
    );
    if (retried.statusCode == 401) {
      await retried.stream.drain<void>();
      await _tokenStore.clear();
      onSessionExpired?.call();
      throw const SessionExpiredException();
    }
    return retried;
  }

  Future<AuthTokens> _refresh(AuthTokens failedTokens) {
    final active = _refreshInFlight;
    if (active != null) {
      return active;
    }
    late final Future<AuthTokens> future;
    future = _performRefresh(failedTokens).whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = future;
    return future;
  }

  Future<AuthTokens> _performRefresh(AuthTokens failedTokens) async {
    try {
      final tokens = await _refreshTokens(failedTokens.refreshToken);
      await _tokenStore.write(tokens);
      return tokens;
    } catch (_) {
      await _tokenStore.clear();
      onSessionExpired?.call();
      throw const SessionExpiredException();
    }
  }

  static bool _hasSameOrigin(Uri candidate, Uri base) =>
      candidate.scheme == base.scheme &&
      candidate.host == base.host &&
      candidate.port == base.port;

  @override
  void close() => _inner.close();
}

class _RequestSnapshot {
  const _RequestSnapshot({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
    required this.followRedirects,
    required this.maxRedirects,
    required this.persistentConnection,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final bool followRedirects;
  final int maxRedirects;
  final bool persistentConnection;

  static Future<_RequestSnapshot> capture(http.BaseRequest request) async =>
      _RequestSnapshot(
        method: request.method,
        url: request.url,
        headers: Map<String, String>.from(request.headers),
        bodyBytes: await request.finalize().toBytes(),
        followRedirects: request.followRedirects,
        maxRedirects: request.maxRedirects,
        persistentConnection: request.persistentConnection,
      );

  http.Request create({String? accessToken}) {
    final request = http.Request(method, url)
      ..headers.addAll(headers)
      ..bodyBytes = bodyBytes
      ..followRedirects = followRedirects
      ..maxRedirects = maxRedirects
      ..persistentConnection = persistentConnection;
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    return request;
  }
}
