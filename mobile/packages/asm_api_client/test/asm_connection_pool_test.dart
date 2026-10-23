import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Retryable requests (GET, HEAD, or carrying an Idempotency-Key) share one
/// pool of connections across every AsmApiClient, kept for
/// [AsmConnectionPool.idleTimeout]. Every other request gets a connection of
/// its own that is closed after the response. A real loopback server counts
/// the client ports it sees: the same port means the same connection.
void main() {
  late _CountingServer server;

  setUp(() async {
    AsmConnectionPool.resetForTesting();
    server = await _CountingServer.start();
  });

  tearDown(() async {
    AsmConnectionPool.resetForTesting();
    await server.close();
  });

  AsmApiClient client({Duration receiveTimeout = const Duration(seconds: 10)}) {
    return AsmApiClient(
      baseUrl: server.baseUrl,
      receiveTimeout: receiveTimeout,
      requestTimeout: const Duration(seconds: 15),
    );
  }

  test('two clients, two GETs 5 s apart: one connection', () async {
    await client().get<Object?>('/ok');
    await Future<void>.delayed(const Duration(seconds: 5));
    await client().get<Object?>('/ok');

    expect(server.ports, hasLength(2));
    expect(server.ports.toSet(), hasLength(1));
  });

  test('one client, two GETs 5 s apart: one connection', () async {
    final api = client();
    await api.get<Object?>('/ok');
    await Future<void>.delayed(const Duration(seconds: 5));
    await api.get<Object?>('/ok');

    expect(server.ports.toSet(), hasLength(1));
  });

  test('closing one client does not close the pool for the others', () async {
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl))
      ..httpClientAdapter = AsmConnectionRouter();
    await dio.get<Object?>('/ok');
    dio.close(force: true);

    final response = await client().get<Object?>('/ok');

    expect(response.isSuccess, isTrue);
    expect(server.ports.toSet(), hasLength(1));
  });

  test('a connection idle longer than the limit is not reused', () async {
    AsmConnectionPool.resetForTesting(
      idleTimeout: const Duration(milliseconds: 500),
    );
    final api = client();
    await api.get<Object?>('/ok');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await api.get<Object?>('/ok');

    expect(server.ports.toSet(), hasLength(2));
  });

  test('the idle limit is not above 20 s', () {
    expect(
      AsmConnectionPool.idleTimeout,
      lessThanOrEqualTo(const Duration(seconds: 20)),
    );
    expect(
      AsmConnectionPool.effectiveIdleTimeout,
      AsmConnectionPool.idleTimeout,
    );
  });

  test('after the server closes an idle connection, the next request succeeds '
      'on a new one', () async {
    server.httpServer.idleTimeout = const Duration(milliseconds: 300);
    final api = client();
    await api.get<Object?>('/ok');
    await Future<void>.delayed(const Duration(seconds: 1));

    final response = await api.get<Object?>('/ok');

    expect(response.isSuccess, isTrue);
    expect(server.ports.toSet(), hasLength(2));
  });

  test('a client given its own Dio keeps its own adapter', () {
    final adapter = _NeverAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    AsmApiClient(baseUrl: server.baseUrl, dio: dio);

    expect(dio.httpClientAdapter, same(adapter));
  });

  test(
    'each client keeps its own receive timeout on the shared pool',
    () async {
      final impatient = client(receiveTimeout: const Duration(seconds: 1));
      final patient = client(receiveTimeout: const Duration(seconds: 5));

      final results = await Future.wait([
        impatient.get<Object?>('/slow'),
        patient.get<Object?>('/slow'),
      ]);

      expect(results[0].isSuccess, isFalse);
      expect(results[0].error?.type, AsmApiExceptionType.timeout);
      expect(results[1].isSuccess, isTrue);
    },
  );

  group('requests that cannot be retried', () {
    test('a keyless POST never uses a pooled connection', () async {
      final api = client();
      await api.get<Object?>('/ok');
      await api.post<Object?>('/ok', data: const <String, Object?>{});
      await api.get<Object?>('/ok');

      // GET, POST, GET: the POST had a connection of its own, and the
      // second GET still found the first GET's connection.
      expect(server.ports, hasLength(3));
      expect(server.ports[0], server.ports[2]);
      expect(server.ports[1], isNot(server.ports[0]));
    });

    test('two keyless POSTs 1 s apart use two connections', () async {
      final api = client();
      await api.post<Object?>('/ok', data: const <String, Object?>{});
      await Future<void>.delayed(const Duration(seconds: 1));
      await api.post<Object?>('/ok', data: const <String, Object?>{});

      expect(server.ports.toSet(), hasLength(2));
    });

    test('a POST with an Idempotency-Key uses the pool', () async {
      final api = client();
      await api.get<Object?>('/ok');
      await api.post<Object?>(
        '/ok',
        data: const <String, Object?>{},
        headers: const <String, String>{'Idempotency-Key': 'key-1'},
      );

      expect(server.ports.toSet(), hasLength(1));
    });

    test('which requests count as retryable', () {
      RequestOptions options(String method, [Map<String, dynamic>? headers]) =>
          RequestOptions(path: '/', method: method, headers: headers);

      expect(AsmConnectionPool.isRetryable(options('GET')), isTrue);
      expect(AsmConnectionPool.isRetryable(options('head')), isTrue);
      expect(AsmConnectionPool.isRetryable(options('POST')), isFalse);
      expect(
        AsmConnectionPool.isRetryable(
          options('POST', {'idempotency-key': 'k'}),
        ),
        isTrue,
      );
      expect(
        AsmConnectionPool.isRetryable(
          options('POST', {'Idempotency-Key': ' '}),
        ),
        isFalse,
      );
      expect(
        AsmConnectionPool.isRetryable(options('PATCH', {'Accept': 'x'})),
        isFalse,
      );
    });
  });
}

class _CountingServer {
  _CountingServer(this.httpServer);

  final HttpServer httpServer;
  final List<int> ports = <int>[];

  String get baseUrl => 'http://127.0.0.1:${httpServer.port}';

  static Future<_CountingServer> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _CountingServer(httpServer);
    httpServer.listen((request) async {
      server.ports.add(request.connectionInfo!.remotePort);
      await request.drain<void>();
      if (request.uri.path == '/slow') {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, Object?>{'ok': true}));
      await request.response.close();
    });
    return server;
  }

  Future<void> close() => httpServer.close(force: true);
}

class _NeverAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw UnimplementedError();
  }

  @override
  void close({bool force = false}) {}
}
