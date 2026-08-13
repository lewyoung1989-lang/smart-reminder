import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/family_models.dart';

class FamilyApi {
  FamilyApi({required String baseUrl, http.Client? client})
      : _baseUri = Uri.parse(baseUrl),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;
  static const _headers = {'Content-Type': 'application/json'};

  Future<FamilyInfo?> getCurrent() async {
    final response = await _client.get(
      _baseUri.resolve('/api/v1/families/current'),
      headers: _headers,
    );
    _expect(response, 200);
    final value = (_decode(response) as Map<String, dynamic>)['family'];
    return value == null
        ? null
        : FamilyInfo.fromJson(value as Map<String, dynamic>);
  }

  Future<FamilyInfo> create({required String name, required String nickname}) =>
      _familyRequest(
          'POST',
          '/api/v1/families/current',
          {
            'name': name,
            'nickname': nickname,
          },
          expected: 201);

  Future<FamilyInfo> join({required String code, required String nickname}) =>
      _familyRequest(
          'POST',
          '/api/v1/families/join',
          {
            'code': code,
            'nickname': nickname,
          },
          expected: 201);

  Future<FamilyInvitation> invite() async {
    final response = await _client.post(
      _baseUri.resolve('/api/v1/families/invitations'),
      headers: _headers,
      body: '{}',
    );
    _expect(response, 201);
    final json = _decode(response) as Map<String, dynamic>;
    return FamilyInvitation(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Future<void> leave() async =>
      _emptyRequest('DELETE', '/api/v1/families/membership');

  Future<void> disband() async =>
      _emptyRequest('DELETE', '/api/v1/families/current');

  Future<void> removeMember(String id) async => _emptyRequest(
      'DELETE', '/api/v1/families/members/${Uri.encodeComponent(id)}');

  Future<FamilyInfo> transferAdmin(String memberId) => _familyRequest(
        'POST',
        '/api/v1/families/transfer-admin',
        {'member_id': memberId},
      );

  Future<FamilyInfo> _familyRequest(
    String method,
    String path,
    Map<String, Object?> body, {
    int expected = 200,
  }) async {
    final request = http.Request(method, _baseUri.resolve(path))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);
    final response =
        await http.Response.fromStream(await _client.send(request));
    _expect(response, expected);
    return FamilyInfo.fromJson(_decode(response) as Map<String, dynamic>);
  }

  Future<void> _emptyRequest(String method, String path) async {
    final response = await http.Response.fromStream(
      await _client.send(http.Request(method, _baseUri.resolve(path))),
    );
    _expect(response, 204);
  }

  static void _expect(http.Response response, int expected) {
    if (response.statusCode != expected) {
      throw FamilyApiException(response.statusCode, response.body);
    }
  }

  static Object? _decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes));

  void close() {
    if (_ownsClient) _client.close();
  }
}

class FamilyApiException implements Exception {
  const FamilyApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
