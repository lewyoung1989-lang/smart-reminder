import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_reminder_app/features/family/data/family_api.dart';

void main() {
  test('loads an account without a family', () async {
    final api = FamilyApi(
      baseUrl: 'https://api.invalid',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/families/current');
        return http.Response(jsonEncode({'family': null}), 200);
      }),
    );

    expect(await api.getCurrent(), isNull);
  });

  test('creates and joins a family with explicit identity fields', () async {
    final requests = <http.Request>[];
    final payload = {
      'id': 'family-1',
      'name': '刘家药箱',
      'role': 'admin',
      'members': [
        {
          'id': 'member-1',
          'nickname': '爸爸',
          'phone_masked': '138****0001',
          'role': 'admin',
          'is_self': true,
        }
      ],
    };
    final api = FamilyApi(
      baseUrl: 'https://api.invalid',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          utf8.encode(jsonEncode(payload)),
          201,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final created = await api.create(name: '刘家药箱', nickname: '爸爸');
    await api.join(code: '123456', nickname: '妈妈');

    expect(created.name, '刘家药箱');
    expect(created.members.single.phoneMasked, '138****0001');
    expect(jsonDecode(requests[0].body), {
      'name': '刘家药箱',
      'nickname': '爸爸',
    });
    expect(jsonDecode(requests[1].body), {
      'code': '123456',
      'nickname': '妈妈',
    });
  });
}
