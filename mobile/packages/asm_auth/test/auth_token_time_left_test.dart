import 'dart:convert';

import 'package:asm_auth/asm_auth.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Map<String, Object?> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.signature';
}

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  int seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  test('reads the token\'s own exp', () {
    final token = _jwt({
      'token_type': 'refresh',
      'exp': seconds(now.add(const Duration(hours: 11, minutes: 30))),
    });
    expect(
      authTokenTimeLeft(token, now: now),
      const Duration(hours: 11, minutes: 30),
    );
  });

  test('an expired token has zero left', () {
    final token = _jwt({
      'exp': seconds(now.subtract(const Duration(hours: 1))),
    });
    expect(authTokenTimeLeft(token, now: now), Duration.zero);
  });

  test('no token, no exp, or an unreadable token: unknown', () {
    expect(authTokenTimeLeft(null, now: now), isNull);
    expect(authTokenTimeLeft('', now: now), isNull);
    expect(
      authTokenTimeLeft(_jwt({'token_type': 'refresh'}), now: now),
      isNull,
    );
    expect(authTokenTimeLeft('not-a-jwt', now: now), isNull);
    expect(authTokenTimeLeft('a.b@d.c', now: now), isNull);
    expect(authTokenTimeLeft(_jwt({'exp': 'soon'}), now: now), isNull);
  });
}
