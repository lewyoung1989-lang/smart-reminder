import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ocr_job.dart';

class _UploadGrant {
  const _UploadGrant(this.objectKey, this.url, this.headers);

  final String objectKey;
  final Uri url;
  final Map<String, String> headers;
}

class MedicineOcrApi {
  MedicineOcrApi({
    required this.baseUrl,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Map<String, String> get _apiHeaders => {
        'Content-Type': 'application/json',
      };

  Future<_UploadGrant> _createUpload(
    String kind,
    List<int> bytes,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/ocr/uploads'),
      headers: _apiHeaders,
      body: jsonEncode({
        'kind': kind,
        'content_type': 'image/jpeg',
        'byte_length': bytes.length,
      }),
    );
    if (response.statusCode != 201) {
      throw MedicineOcrApiException(response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _UploadGrant(
      json['object_key'] as String,
      Uri.parse(json['upload_url'] as String),
      Map<String, String>.from(json['headers'] as Map),
    );
  }

  Future<String> _upload(String kind, List<int> bytes) async {
    final grant = await _createUpload(kind, bytes);
    // 签名 PUT 只能携带存储服务返回的头，绝不能泄露 API Bearer Token。
    final response = await _client.put(
      grant.url,
      headers: grant.headers,
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MedicineOcrApiException(response.statusCode);
    }
    return grant.objectKey;
  }

  Future<OcrJob> createJob({
    required List<int> frontBytes,
    List<int>? expiryBytes,
  }) async {
    final images = <Map<String, String>>[
      {
        'kind': 'front',
        'object_key': await _upload('front', frontBytes),
      },
    ];
    if (expiryBytes != null) {
      images.add({
        'kind': 'expiry',
        'object_key': await _upload('expiry', expiryBytes),
      });
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/ocr/jobs'),
      headers: _apiHeaders,
      body: jsonEncode({'images': images}),
    );
    if (response.statusCode != 201) {
      throw MedicineOcrApiException(response.statusCode);
    }
    return OcrJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<OcrJob> getJob(String id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/ocr/jobs/$id'),
      headers: _apiHeaders,
    );
    if (response.statusCode != 200) {
      throw MedicineOcrApiException(response.statusCode);
    }
    return OcrJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> confirmJob(
    String id,
    Map<String, Object?> fields,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/ocr/jobs/$id/confirm'),
      headers: _apiHeaders,
      body: jsonEncode(fields),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw MedicineOcrApiException(response.statusCode);
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class MedicineOcrApiException implements Exception {
  const MedicineOcrApiException(this.statusCode);

  final int statusCode;
}
