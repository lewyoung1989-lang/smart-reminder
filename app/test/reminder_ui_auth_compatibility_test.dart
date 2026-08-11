import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_reminder_app/app/theme/app_theme.dart';
import 'package:smart_reminder_app/core/network/authenticated_client.dart';
import 'package:smart_reminder_app/features/auth/data/token_store.dart';
import 'package:smart_reminder_app/features/auth/domain/auth_models.dart';
import 'package:smart_reminder_app/features/quick_create/presentation/quick_create_sheet.dart';
import 'package:smart_reminder_app/features/reminder_drafts/application/reminder_creation_service.dart';
import 'package:smart_reminder_app/features/reminder_drafts/data/reminder_draft_api.dart';

class _TokenStore implements TokenStore {
  _TokenStore(this.tokens);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

void main() {
  testWidgets('redesigned quick create uses the authenticated draft client', (
    tester,
  ) async {
    late http.Request request;
    final client = AuthenticatedClient(
      apiBaseUri: Uri.parse('https://api.invalid'),
      inner: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'id': 'draft-1',
            'parser_source': 'local',
            'draft': {
              'title': '喝水',
              'schedule': {
                'local_datetime': '2026-08-07T10:01:00+08:00',
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
      }),
      tokenStore: _TokenStore(
        const AuthTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          accessExpiresIn: 900,
        ),
      ),
      refreshTokens: (_) async => throw UnimplementedError(),
    );
    final api = ReminderDraftApi(
      baseUrl: 'https://api.invalid',
      client: client,
    );
    final creationService = ReminderCreationService(
      confirmDraft: api.confirmDraft,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: QuickCreateSheet(
            createDraft: api.createDraft,
            onParsed: (result) {
              expect(result.draft.reminder!.id, 'draft-1');
              expect(creationService, isA<ReminderCreationService>());
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('quick-create-input')),
      '1分钟后提醒我喝水',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(request.headers['Authorization'], 'Bearer access-token');
    expect(jsonDecode(request.body), {'text': '1分钟后提醒我喝水'});
  });
}
