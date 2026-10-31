// B8 assembly tests: the trusted contact and the safety alert exactly as
// DriverApp builds them in production (not injected), down to the HTTP
// request. dart:io's HttpOverrides gives every HttpClient a fake that
// records the request and answers it; nothing opens a socket.
//
// Production's objects send only with a configured server address, a
// compile-time define. Run:
//   flutter test test/driver_assembly_test.dart \
//     --dart-define=ASM_API_BASE_URL=https://assembly-test.alanteh.invalid
// The .invalid host can never resolve, so even a missed override could not
// reach a real server. Without the define the tests are skipped.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/safety/driver_trip_safety.dart';
import 'package:flutter_test/flutter_test.dart';

const _assemblyBaseUrl = 'https://assembly-test.alanteh.invalid';
const _skip = AsmApiClient.defaultBaseUrl == _assemblyBaseUrl
    ? false
    : 'run with --dart-define=ASM_API_BASE_URL=$_assemblyBaseUrl';

final _http = _FakeHttp();

void main() {
  late HttpOverrides? previous;

  setUp(() {
    _http.requests.clear();
    previous = HttpOverrides.current;
    HttpOverrides.global = _http;
  });
  tearDown(() => HttpOverrides.global = previous);

  testWidgets(
    'trusted contact save: production object, real path, body and Bearer',
    (tester) async {
      _http.answer = (_) => (
        status: 200,
        body: <String, Object?>{
          'emergency_contact_name': 'Assembly Contact',
          'emergency_contact_phone': '+233200000000',
        },
      );
      final shell = await _pumpProductionApp(tester);
      final repository = shell.driverTrustedContactRepository!;
      expect(repository, isA<ApiDriverTrustedContactRepository>());

      final saved = await tester.runAsync(
        () => repository.save(name: 'Assembly Contact', phone: '+233200000000'),
      );

      expect(saved?.name, 'Assembly Contact');
      final request = _http.requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.toString(), '$_assemblyBaseUrl/api/driver/profile/');
      expect(request.headers['authorization'], 'Bearer assembly-access');
      expect(jsonDecode(utf8.decode(request.body)), <String, Object?>{
        'emergency_contact_name': 'Assembly Contact',
        'emergency_contact_phone': '+233200000000',
      });
    },
    skip: _skip != false,
  );

  testWidgets(
    'safety alert: production object, real path, body and Bearer',
    (tester) async {
      _http.answer = (_) => (status: 201, body: <String, Object?>{'id': 1});
      final shell = await _pumpProductionApp(tester);
      final repository = shell.driverSafetyAlertRepository!;
      expect(repository, isA<ApiDriverSafetyAlertRepository>());

      await tester.runAsync(
        () => repository.send(
          tripReference: 'TRIP-ASSEMBLY',
          latitude: 5.6037,
          longitude: -0.187,
        ),
      );

      final request = _http.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        '$_assemblyBaseUrl/api/driver/safety-alert/',
      );
      expect(request.headers['authorization'], 'Bearer assembly-access');
      expect(jsonDecode(utf8.decode(request.body)), <String, Object?>{
        'trip_reference': 'TRIP-ASSEMBLY',
        'latitude': '5.6037',
        'longitude': '-0.187',
      });
    },
    skip: _skip != false,
  );
}

/// The app as production builds it, except the token store (a signed-in
/// one in memory); the shell holds the objects DriverApp made.
Future<DriverShell> _pumpProductionApp(WidgetTester tester) async {
  final tokens = MemoryAuthTokenStore();
  await tokens.saveTokens(
    AuthTokens(accessToken: 'assembly-access', refreshToken: 'assembly-ref'),
  );
  await tester.pumpWidget(DriverApp(authTokenStore: tokens));
  await tester.pump();
  return tester.widget<DriverShell>(find.byType(DriverShell));
}

typedef _Answer = ({int status, Map<String, Object?> body});

final class _Request {
  _Request(this.method, this.url);

  final String method;
  final Uri url;
  final headers = <String, String>{};
  final body = <int>[];
}

final class _FakeHttp extends HttpOverrides {
  final requests = <_Request>[];
  _Answer Function(_Request request) answer = (_) =>
      (status: 500, body: const <String, Object?>{});

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(this);
}

final class _FakeClient implements HttpClient {
  _FakeClient(this._http);

  final _FakeHttp _http;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(_http, _Request(method, url));

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('fake HttpClient: ${invocation.memberName}');
}

final class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._http, this._request);

  final _FakeHttp _http;
  final _Request _request;

  @override
  late final HttpHeaders headers = _FakeHeaders(_request.headers);

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  String get method => _request.method;

  @override
  Uri get uri => _request.url;

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_request.body.addAll);

  @override
  Future<HttpClientResponse> close() async {
    _http.requests.add(_request);
    final answer = _http.answer(_request);
    return _FakeResponse(answer.status, utf8.encode(jsonEncode(answer.body)));
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('fake request: ${invocation.memberName}');
}

final class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this._values);

  final Map<String, String> _values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = '$value';

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = '$value';

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach((name, value) => action(name, [value]));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('fake headers: ${invocation.memberName}');
}

final class _FakeResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeResponse(this.statusCode, this._body);

  final List<int> _body;

  @override
  final int statusCode;

  @override
  String get reasonPhrase => statusCode < 300 ? 'OK' : 'Error';

  @override
  late final HttpHeaders headers = _FakeHeaders(<String, String>{
    'content-type': 'application/json; charset=utf-8',
  });

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  int get contentLength => _body.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('fake response: ${invocation.memberName}');
}
