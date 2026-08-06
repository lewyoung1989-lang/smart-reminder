import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../domain/voice_transcription.dart';

class VoiceTranscriptionApi {
  VoiceTranscriptionApi({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final String accessToken;
  final http.Client _client;
  final bool _ownsClient;

  Future<VoiceTranscription> transcribe(String audioPath) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/api/v1/voice/transcriptions',
      ),
    )
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..files.add(
        await http.MultipartFile.fromPath(
          'audio',
          audioPath,
          contentType: MediaType('audio', 'wav'),
        ),
      );

    final response =
        await http.Response.fromStream(await _client.send(request));
    if (response.statusCode != 200) {
      throw VoiceTranscriptionApiException(
        response.statusCode,
        _extractErrorCode(response.body),
      );
    }
    return VoiceTranscription.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _extractErrorCode(String body) {
    try {
      final payload = jsonDecode(body);
      if (payload is Map<String, dynamic> && payload['code'] is String) {
        return payload['code'] as String;
      }
    } on FormatException {
      // Fall through to a stable local error code.
    }
    return 'unknown_error';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class VoiceTranscriptionApiException implements Exception {
  const VoiceTranscriptionApiException(this.statusCode, this.code);

  final int statusCode;
  final String code;

  @override
  String toString() => 'VoiceTranscriptionApiException($statusCode, $code)';
}
