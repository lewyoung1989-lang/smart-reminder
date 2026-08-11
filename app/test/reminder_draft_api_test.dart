import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_reminder_app/features/reminder_drafts/data/reminder_draft_api.dart';

void main() {
  test('create draft delegates authentication to its client', () async {
    late http.Request recorded;
    final client = MockClient((request) async {
      recorded = request;
      return http.Response(
        jsonEncode({
          'id': 'draft-1',
          'parser_source': 'local',
          'draft': {
            'title': '喝水',
            'schedule': {
              'local_datetime': '2026-08-04T10:01:00+08:00',
              'timezone': 'Asia/Shanghai',
            },
            'severity': 'notification',
            'condition_met_message': null,
            'ambiguities': [],
          },
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ReminderDraftApi(
      baseUrl: 'http://192.168.1.10:8000',
      client: client,
    );

    final draft = await api.createDraft('1分钟后提醒我喝水');

    expect(recorded.method, 'POST');
    expect(recorded.url.toString(),
        'http://192.168.1.10:8000/api/v1/reminder-drafts');
    expect(recorded.headers['Authorization'], isNull);
    expect(jsonDecode(recorded.body), {'text': '1分钟后提醒我喝水'});
    expect(draft.reminder!.title, '喝水');
    expect(draft.reminder!.parserSource, 'local');
  });

  test('confirm draft returns the idempotent reminder id', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'http://127.0.0.1:8000/api/v1/reminder-drafts/draft-1/confirm',
      );
      return http.Response(
        jsonEncode({'reminder_id': 'reminder-1', 'status': 'confirmed'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ReminderDraftApi(
      baseUrl: 'http://127.0.0.1:8000',
      client: client,
    );

    expect(await api.confirmDraft('draft-1'), 'reminder-1');
  });
}
