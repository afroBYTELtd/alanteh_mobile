import 'dart:async';
import 'dart:convert';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:driver_app/concern/driver_concern_page.dart';
import 'package:driver_app/network/driver_report_gateway.dart';
import 'package:driver_app/network/driver_trip_action_gateway.dart';
import 'package:driver_app/network/ghana_network_resilience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test_report_submits_to_backend_endpoint', () async {
    final accessToken = _jwtExpiringAt(DateTime.utc(2100));
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(
      AuthTokens(
        accessToken: accessToken,
        refreshToken: 'synthetic-driver-report-refresh',
      ),
    );

    final api = _RecordingDriverReportApi(
      categoryPayload: const <String, Object?>{
        'categories': <String>[
          'Vehicle concern',
          'Safety issue',
          'Route issue',
          'Passenger concern',
          'Other',
        ],
      },
      reportPayload: const <String, Object?>{
        'report_reference': 'RPT-ABCDEFGHIJ',
        'status': 'received',
      },
    );
    final gateway = ApiDriverReportGateway(
      apiGateway: api,
      tokenStore: tokenStore,
    );

    final receipt = await gateway.submit(
      category: 'Vehicle concern',
      description: 'Mirror vibration noted',
      urgency: 'urgent',
    );

    expect(receipt.reportReference, 'RPT-ABCDEFGHIJ');
    expect(api.postCalls, 1);
    expect(api.postPaths, <String>[driverReportSubmissionPath]);
    expect(api.postBodies.single, <String, Object?>{
      'category': 'Vehicle concern',
      'description': 'Mirror vibration noted',
      'urgency': 'urgent',
    });
    expect(api.postHeaders.single['Content-Type'], 'application/json');
    expect(api.postHeaders.single['Authorization'], 'Bearer $accessToken');
  });

  test('test_categories_fetched_from_driver_report_categories_api', () async {
    final api = _RecordingDriverReportApi(
      categoryPayload: const <String, Object?>{
        'categories': <String>[
          'Vehicle concern',
          'Safety issue',
          'Route issue',
          'Passenger concern',
          'Other',
        ],
      },
      reportPayload: const <String, Object?>{
        'report_reference': 'RPT-ABCDEFGHIJ',
        'status': 'received',
      },
    );
    final gateway = ApiDriverReportGateway(
      apiGateway: api,
      tokenStore: MemoryAuthTokenStore(),
    );

    final first = await gateway.fetchCategories();
    final second = await gateway.fetchCategories();

    expect(first, <String>[
      'Vehicle concern',
      'Safety issue',
      'Route issue',
      'Passenger concern',
      'Other',
    ]);
    expect(second, first);
    expect(api.getCalls, 1);
    expect(api.getPaths, <String>[driverReportCategoriesPath]);
  });

  testWidgets('test_success_shows_rpt_reference', (tester) async {
    _useSurface(tester);
    final gateway = _WidgetDriverReportGateway();

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverConcernPage(
          market: MarketConfig.ghanaAccra,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _completeReportForm(tester, description: 'Battery warning noted');

    await tester.ensureVisible(find.byKey(const Key('send-concern')));
    await tester.tap(find.byKey(const Key('send-concern')));
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, 1);
    expect(find.text('Your report has been received.'), findsOneWidget);
    expect(find.byKey(const Key('concern-report-reference')), findsOneWidget);
    expect(find.text('RPT-ABCDEFGHIJ'), findsOneWidget);
  });

  testWidgets('test_continue_without_sending_absent', (tester) async {
    _useSurface(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverConcernPage(
          market: MarketConfig.ghanaAccra,
          gateway: _WidgetDriverReportGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue without sending'), findsNothing);
    expect(find.text('Review report'), findsNothing);
    expect(
      find.text('This report is not sent from the app yet.'),
      findsNothing,
    );
    expect(find.byKey(const Key('send-concern')), findsOneWidget);
  });

  testWidgets('test_failure_shows_retry', (tester) async {
    _useSurface(tester);
    final gateway = _WidgetDriverReportGateway(
      submitError: const DriverReportException(
        type: DriverReportFailureType.temporarilyUnavailable,
        message:
            'Your report could not be sent. '
            'Check your connection and retry.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverConcernPage(
          market: MarketConfig.ghanaAccra,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _completeReportForm(tester, description: 'Route obstruction noted');

    await tester.ensureVisible(find.byKey(const Key('send-concern')));
    await tester.tap(find.byKey(const Key('send-concern')));
    await tester.pumpAndSettle();

    expect(gateway.submitCalls, 1);
    expect(find.byKey(const Key('concern-submission-error')), findsOneWidget);
    expect(find.byKey(const Key('retry-concern-submission')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    final descriptionField = tester.widget<TextFormField>(
      find.byKey(const Key('concern-description')),
    );
    expect(descriptionField.controller?.text, 'Route obstruction noted');
    expect(find.byKey(const Key('concern-submitted')), findsNothing);
  });

  test('report transport failure is not automatically retried', () async {
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(
      AuthTokens(
        accessToken: _jwtExpiringAt(DateTime.utc(2100)),
        refreshToken: 'synthetic-driver-report-refresh',
      ),
    );
    final api = _FailingPostDriverReportApi();
    final gateway = ApiDriverReportGateway(
      apiGateway: api,
      tokenStore: tokenStore,
      retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
    );

    await expectLater(
      gateway.submit(
        category: 'Vehicle concern',
        description: 'Mirror vibration noted',
        urgency: 'urgent',
      ),
      throwsA(
        isA<DriverReportException>().having(
          (error) => error.type,
          'type',
          DriverReportFailureType.temporarilyUnavailable,
        ),
      ),
    );

    expect(api.postCalls, 1);
  });

  test('category GET safely retries a transient failure', () async {
    final api = _RetryingCategoryDriverReportApi();
    final gateway = ApiDriverReportGateway(
      apiGateway: api,
      tokenStore: MemoryAuthTokenStore(),
      retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
    );

    final categories = await gateway.fetchCategories();

    expect(api.getCalls, 2);
    expect(categories, <String>[
      'Vehicle concern',
      'Safety issue',
      'Route issue',
      'Passenger concern',
      'Other',
    ]);
  });

  test('category cache clears with the Driver session', () async {
    final api = _RecordingDriverReportApi(
      categoryPayload: const <String, Object?>{
        'categories': <String>[
          'Vehicle concern',
          'Safety issue',
          'Route issue',
          'Passenger concern',
          'Other',
        ],
      },
      reportPayload: const <String, Object?>{
        'report_reference': 'RPT-ABCDEFGHIJ',
        'status': 'received',
      },
    );
    final gateway = ApiDriverReportGateway(
      apiGateway: api,
      tokenStore: MemoryAuthTokenStore(),
    );

    await gateway.fetchCategories();
    await gateway.fetchCategories();
    expect(api.getCalls, 1);

    gateway.clearSessionCache();
    await gateway.fetchCategories();

    expect(api.getCalls, 2);
  });

  test('401 refreshes once and retries the report once', () async {
    final initialAccessToken = _jwtExpiringAt(DateTime.utc(2100));
    final refreshedAccessToken = _jwtExpiringAt(DateTime.utc(2101));
    final tokenStore = MemoryAuthTokenStore();
    await tokenStore.saveTokens(
      AuthTokens(
        accessToken: initialAccessToken,
        refreshToken: 'synthetic-driver-report-refresh',
      ),
    );

    final api = _UnauthorizedThenSuccessDriverReportApi();
    var refreshCalls = 0;
    final gateway = ApiDriverReportGateway(
      apiGateway: api,
      tokenStore: tokenStore,
      retryPolicy: GhanaRetryPolicy(delay: (_) async {}),
      refreshAccessToken: () async {
        refreshCalls += 1;
        await tokenStore.saveTokens(
          AuthTokens(
            accessToken: refreshedAccessToken,
            refreshToken: 'synthetic-driver-report-refresh',
          ),
        );
        return DriverTokenRefreshOutcome.refreshed;
      },
    );

    final receipt = await gateway.submit(
      category: 'Vehicle concern',
      description: 'Mirror vibration noted',
      urgency: 'urgent',
    );

    expect(receipt.reportReference, 'RPT-ABCDEFGHIJ');
    expect(refreshCalls, 1);
    expect(api.postCalls, 2);
    expect(api.postHeaders, hasLength(2));
    expect(
      api.postHeaders.first['Authorization'],
      'Bearer $initialAccessToken',
    );
    expect(
      api.postHeaders.last['Authorization'],
      'Bearer $refreshedAccessToken',
    );
  });

  testWidgets('category load failure shows Retry and recovers', (tester) async {
    _useSurface(tester);
    final gateway = _CategoryRetryWidgetDriverReportGateway();

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverConcernPage(
          market: MarketConfig.ghanaAccra,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('concern-categories-error')), findsOneWidget);
    expect(find.byKey(const Key('retry-concern-categories')), findsOneWidget);
    expect(gateway.categoryCalls, 1);

    await tester.tap(find.byKey(const Key('retry-concern-categories')));
    await tester.pumpAndSettle();

    expect(gateway.categoryCalls, 2);
    expect(find.byKey(const Key('concern-categories-error')), findsNothing);
    expect(find.byKey(const Key('concern-category')), findsOneWidget);
  });

  testWidgets('duplicate in-flight report submission is prevented', (
    tester,
  ) async {
    _useSurface(tester);
    final gateway = _DeferredWidgetDriverReportGateway();

    await tester.pumpWidget(
      MaterialApp(
        theme: AsmThemes.driver,
        home: DriverConcernPage(
          market: MarketConfig.ghanaAccra,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _completeReportForm(tester, description: 'Battery warning noted');
    await tester.ensureVisible(find.byKey(const Key('send-concern')));

    await tester.tap(find.byKey(const Key('send-concern')));
    await tester.pump();

    expect(gateway.submitCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('send-concern')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('send-concern')));
    await tester.pump();
    expect(gateway.submitCalls, 1);

    gateway.completeSuccess();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('concern-submitted')), findsOneWidget);
    expect(find.text('Your report has been received.'), findsOneWidget);
  });
}

final class _FailingPostDriverReportApi implements DriverReportApiGateway {
  int postCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    throw StateError('GET not used by this test.');
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;
    return ApiResponse<T>.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.network,
        message: 'Synthetic network failure.',
      ),
    );
  }
}

final class _RetryingCategoryDriverReportApi implements DriverReportApiGateway {
  int getCalls = 0;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    getCalls += 1;

    if (getCalls == 1) {
      return ApiResponse<T>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.network,
          message: 'Synthetic network failure.',
        ),
      );
    }

    final decoded = decoder!(const <String, Object?>{
      'categories': <String>[
        'Vehicle concern',
        'Safety issue',
        'Route issue',
        'Passenger concern',
        'Other',
      ],
    });

    return ApiResponse<T>.success(decoded, statusCode: 200);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) {
    throw StateError('POST not used by this test.');
  }
}

final class _UnauthorizedThenSuccessDriverReportApi
    implements DriverReportApiGateway {
  int postCalls = 0;
  final List<Map<String, String>> postHeaders = <Map<String, String>>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    throw StateError('GET not used by this test.');
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;
    postHeaders.add(Map<String, String>.of(headers ?? const {}));

    if (postCalls == 1) {
      return ApiResponse<T>.apiFailure(
        const AsmApiException(
          type: AsmApiExceptionType.authentication,
          message: 'Synthetic unauthorized response.',
          statusCode: 401,
        ),
      );
    }

    final decoded = decoder!(const <String, Object?>{
      'report_reference': 'RPT-ABCDEFGHIJ',
      'status': 'received',
    });

    return ApiResponse<T>.success(decoded, statusCode: 201);
  }
}

final class _CategoryRetryWidgetDriverReportGateway
    implements DriverReportGateway {
  int categoryCalls = 0;

  @override
  Future<List<String>> fetchCategories({bool forceRefresh = false}) async {
    categoryCalls += 1;

    if (categoryCalls == 1) {
      throw const DriverReportException(
        type: DriverReportFailureType.temporarilyUnavailable,
        message:
            'Report categories are temporarily unavailable. '
            'Check your connection and retry.',
      );
    }

    return const <String>[
      'Vehicle concern',
      'Safety issue',
      'Route issue',
      'Passenger concern',
      'Other',
    ];
  }

  @override
  Future<DriverReportReceipt> submit({
    required String category,
    required String description,
    required String urgency,
  }) {
    throw StateError('Submit not used by this test.');
  }

  @override
  void clearSessionCache() {}
}

final class _DeferredWidgetDriverReportGateway implements DriverReportGateway {
  final Completer<DriverReportReceipt> _submitCompleter =
      Completer<DriverReportReceipt>();
  int submitCalls = 0;

  @override
  Future<List<String>> fetchCategories({bool forceRefresh = false}) async {
    return const <String>[
      'Vehicle concern',
      'Safety issue',
      'Route issue',
      'Passenger concern',
      'Other',
    ];
  }

  @override
  Future<DriverReportReceipt> submit({
    required String category,
    required String description,
    required String urgency,
  }) {
    submitCalls += 1;
    return _submitCompleter.future;
  }

  void completeSuccess() {
    if (_submitCompleter.isCompleted) {
      return;
    }

    _submitCompleter.complete(
      const DriverReportReceipt(
        reportReference: 'RPT-ABCDEFGHIJ',
        status: 'received',
      ),
    );
  }

  @override
  void clearSessionCache() {}
}

final class _RecordingDriverReportApi implements DriverReportApiGateway {
  _RecordingDriverReportApi({
    required this.categoryPayload,
    required this.reportPayload,
  });

  final Object? categoryPayload;
  final Object? reportPayload;

  int getCalls = 0;
  int postCalls = 0;
  final List<String> getPaths = <String>[];
  final List<String> postPaths = <String>[];
  final List<Object?> postBodies = <Object?>[];
  final List<Map<String, String>> postHeaders = <Map<String, String>>[];

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) async {
    getCalls += 1;
    getPaths.add(path);

    final decoded = decoder!(categoryPayload);
    return ApiResponse<T>.success(decoded, statusCode: 200);
  }

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) async {
    postCalls += 1;
    postPaths.add(path);
    postBodies.add(data);
    postHeaders.add(Map<String, String>.of(headers ?? const {}));

    final decoded = decoder!(reportPayload);
    return ApiResponse<T>.success(decoded, statusCode: 201);
  }
}

final class _WidgetDriverReportGateway implements DriverReportGateway {
  _WidgetDriverReportGateway({this.submitError});

  final DriverReportException? submitError;

  int categoryCalls = 0;
  int submitCalls = 0;
  int clearCalls = 0;

  @override
  Future<List<String>> fetchCategories({bool forceRefresh = false}) async {
    categoryCalls += 1;
    return const <String>[
      'Vehicle concern',
      'Safety issue',
      'Route issue',
      'Passenger concern',
      'Other',
    ];
  }

  @override
  Future<DriverReportReceipt> submit({
    required String category,
    required String description,
    required String urgency,
  }) async {
    submitCalls += 1;

    final error = submitError;
    if (error != null) {
      throw error;
    }

    expect(category, 'Vehicle concern');
    expect(description, isNotEmpty);
    expect(urgency, 'urgent');

    return const DriverReportReceipt(
      reportReference: 'RPT-ABCDEFGHIJ',
      status: 'received',
    );
  }

  @override
  void clearSessionCache() {
    clearCalls += 1;
  }
}

Future<void> _completeReportForm(
  WidgetTester tester, {
  required String description,
}) async {
  await tester.tap(find.byKey(const Key('concern-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Vehicle concern').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('concern-attention')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Urgent').last);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('concern-description')),
    description,
  );
}

String _jwtExpiringAt(DateTime expiry) {
  final header = base64Url.encode(
    utf8.encode(jsonEncode(const <String, Object?>{'alg': 'none'})),
  );
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'exp':
            expiry.toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond,
      }),
    ),
  );

  return '$header.$payload.synthetic';
}

void _useSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
