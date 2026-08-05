import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_reminder_app/features/voice_input/data/voice_transcription_api.dart';

void main() {
  late File audioFile;

  setUp(() async {
    audioFile = File(
      '${Directory.systemTemp.path}/voice-api-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await audioFile.writeAsBytes([0x52, 0x49, 0x46, 0x46]);
  });

  tearDown(() async {
    if (await audioFile.exists()) await audioFile.delete();
  });

  test('uploads WAV multipart with bearer authentication', () async {
    late http.Request recorded;
    final client = MockClient((request) async {
      recorded = request;
      return http.Response(
        jsonEncode({
          'request_id': 'request-1',
          'status': 'completed',
          'transcript': '明天早上提醒我吃药',
          'audio_duration_ms': 500,
          'transcription_latency_ms': 321,
          'provider': 'funasr',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = VoiceTranscriptionApi(
      baseUrl: 'http://192.168.1.10:8000/',
      accessToken: 'local-token',
      client: client,
    );

    final result = await api.transcribe(audioFile.path);

    expect(recorded.method, 'POST');
    expect(
      recorded.url.toString(),
      'http://192.168.1.10:8000/api/v1/voice/transcriptions',
    );
    expect(recorded.headers['Authorization'], 'Bearer local-token');
    expect(
        recorded.headers['content-type'], startsWith('multipart/form-data;'));
    final body = latin1.decode(recorded.bodyBytes);
    expect(body, contains('name="audio"'));
    expect(body, contains('filename="${audioFile.uri.pathSegments.last}"'));
    expect(body.toLowerCase(), contains('content-type: audio/wav'));
    expect(result.requestId, 'request-1');
    expect(result.transcript, '明天早上提醒我吃药');
    expect(result.audioDurationMs, 500);
    expect(result.transcriptionLatencyMs, 321);
    expect(result.provider, 'funasr');
  });

  test('extracts stable code from non-success JSON response', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'code': 'asr_busy'}),
        429,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = VoiceTranscriptionApi(
      baseUrl: 'http://127.0.0.1:8000',
      accessToken: 'local-token',
      client: client,
    );

    expect(
      () => api.transcribe(audioFile.path),
      throwsA(
        isA<VoiceTranscriptionApiException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.code, 'code', 'asr_busy'),
      ),
    );
  });

  test('uses unknown code for malformed error response', () async {
    final client = MockClient((_) async => http.Response('not-json', 502));
    final api = VoiceTranscriptionApi(
      baseUrl: 'http://127.0.0.1:8000',
      accessToken: 'local-token',
      client: client,
    );

    expect(
      () => api.transcribe(audioFile.path),
      throwsA(
        isA<VoiceTranscriptionApiException>().having(
          (error) => error.code,
          'code',
          'unknown_error',
        ),
      ),
    );
  });
}
