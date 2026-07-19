import 'dart:async';
import 'dart:io';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

enum GhanaNetworkStatus { checking, online, offline }

enum GhanaNetworkTransport {
  checking,
  none,
  cellular,
  wifi,
  ethernet,
  vpn,
  satellite,
  bluetooth,
  other,
  mixed,
}

final class GhanaNetworkState {
  const GhanaNetworkState({
    required this.status,
    required this.transport,
    required this.apiReachable,
  });

  static const checking = GhanaNetworkState(
    status: GhanaNetworkStatus.checking,
    transport: GhanaNetworkTransport.checking,
    apiReachable: false,
  );

  final GhanaNetworkStatus status;
  final GhanaNetworkTransport transport;
  final bool apiReachable;

  bool get isOffline => status == GhanaNetworkStatus.offline;

  @override
  bool operator ==(Object other) {
    return other is GhanaNetworkState &&
        other.status == status &&
        other.transport == transport &&
        other.apiReachable == apiReachable;
  }

  @override
  int get hashCode => Object.hash(status, transport, apiReachable);
}

abstract interface class GhanaConnectivitySource {
  Future<List<ConnectivityResult>> checkConnectivity();

  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

final class PluginGhanaConnectivitySource implements GhanaConnectivitySource {
  const PluginGhanaConnectivitySource();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    return Connectivity().checkConnectivity();
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged;
  }
}

final class GhanaNetworkClassifier {
  const GhanaNetworkClassifier._();

  static GhanaNetworkTransport transportFor(List<ConnectivityResult> results) {
    final active = results
        .where((result) => result != ConnectivityResult.none)
        .toSet();

    if (active.isEmpty) {
      return GhanaNetworkTransport.none;
    }
    if (active.length > 1) {
      return GhanaNetworkTransport.mixed;
    }

    return switch (active.single) {
      ConnectivityResult.mobile => GhanaNetworkTransport.cellular,
      ConnectivityResult.wifi => GhanaNetworkTransport.wifi,
      ConnectivityResult.ethernet => GhanaNetworkTransport.ethernet,
      ConnectivityResult.vpn => GhanaNetworkTransport.vpn,
      ConnectivityResult.satellite => GhanaNetworkTransport.satellite,
      ConnectivityResult.bluetooth => GhanaNetworkTransport.bluetooth,
      ConnectivityResult.other => GhanaNetworkTransport.other,
      ConnectivityResult.none => GhanaNetworkTransport.none,
    };
  }
}

typedef GhanaReachabilityProbe =
    Future<bool> Function(Uri endpoint, Duration timeout);

Future<bool> defaultGhanaReachabilityProbe(
  Uri endpoint,
  Duration timeout,
) async {
  final port = endpoint.hasPort
      ? endpoint.port
      : endpoint.scheme == 'https'
      ? 443
      : 80;

  Socket? socket;
  try {
    socket = await Socket.connect(endpoint.host, port, timeout: timeout);
    return true;
  } on Object {
    return false;
  } finally {
    socket?.destroy();
  }
}

final class GhanaApiReachability {
  const GhanaApiReachability({
    required this.baseUrl,
    this.timeout = GhanaRequestPolicy.reachabilityTimeout,
    this.probe = defaultGhanaReachabilityProbe,
  });

  final String? baseUrl;
  final Duration timeout;
  final GhanaReachabilityProbe probe;

  Future<bool> get isOnline async {
    final normalized = baseUrl?.trim();
    if (!AsmApiBaseUrl.isUsable(normalized)) {
      return false;
    }

    return probe(Uri.parse(normalized!), timeout);
  }
}

final class GhanaReachabilityMonitor extends ChangeNotifier {
  GhanaReachabilityMonitor({
    required this.reachability,
    this.connectivitySource = const PluginGhanaConnectivitySource(),
    this.checkInterval = GhanaRequestPolicy.reachabilityCheckInterval,
  });

  final GhanaApiReachability reachability;
  final GhanaConnectivitySource connectivitySource;
  final Duration checkInterval;

  GhanaNetworkState _state = GhanaNetworkState.checking;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _checking = false;
  bool _disposed = false;

  GhanaNetworkState get state => _state;
  GhanaNetworkStatus get status => _state.status;
  GhanaNetworkTransport get transport => _state.transport;

  Future<void> start() async {
    await checkNow();
    if (_disposed) {
      return;
    }

    _connectivitySubscription ??= connectivitySource.onConnectivityChanged
        .listen(
          (results) {
            unawaited(checkNow(observedConnectivity: results));
          },
          onError: (_) {
            unawaited(checkNow());
          },
        );

    _timer ??= Timer.periodic(checkInterval, (_) {
      unawaited(checkNow());
    });
  }

  Future<void> checkNow({
    List<ConnectivityResult>? observedConnectivity,
  }) async {
    if (_checking || _disposed) {
      return;
    }

    _checking = true;
    List<ConnectivityResult> connectivity;
    try {
      connectivity =
          observedConnectivity ?? await connectivitySource.checkConnectivity();
    } on Object {
      connectivity = const <ConnectivityResult>[ConnectivityResult.other];
    }

    final transport = GhanaNetworkClassifier.transportFor(connectivity);
    var apiReachable = false;
    if (transport != GhanaNetworkTransport.none) {
      try {
        apiReachable = await reachability.isOnline;
      } on Object {
        apiReachable = false;
      }
    }
    _checking = false;

    if (_disposed) {
      return;
    }

    final next = GhanaNetworkState(
      status: apiReachable
          ? GhanaNetworkStatus.online
          : GhanaNetworkStatus.offline,
      transport: transport,
      apiReachable: apiReachable,
    );
    if (_state == next) {
      return;
    }

    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    final subscription = _connectivitySubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

class GhanaNetworkStateScope extends InheritedWidget {
  const GhanaNetworkStateScope({
    required this.state,
    required super.child,
    super.key,
  });

  final GhanaNetworkState state;

  static GhanaNetworkState of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<GhanaNetworkStateScope>()
            ?.state ??
        GhanaNetworkState.checking;
  }

  @override
  bool updateShouldNotify(GhanaNetworkStateScope oldWidget) {
    return oldWidget.state != state;
  }
}

class GhanaNetworkStatusBanner extends StatefulWidget {
  const GhanaNetworkStatusBanner({
    required this.baseUrl,
    required this.offlineMessage,
    required this.child,
    this.probe = defaultGhanaReachabilityProbe,
    this.connectivitySource = const PluginGhanaConnectivitySource(),
    this.checkInterval = GhanaRequestPolicy.reachabilityCheckInterval,
    super.key,
  });

  final String? baseUrl;
  final String offlineMessage;
  final Widget child;
  final GhanaReachabilityProbe probe;
  final GhanaConnectivitySource connectivitySource;
  final Duration checkInterval;

  @override
  State<GhanaNetworkStatusBanner> createState() =>
      _GhanaNetworkStatusBannerState();
}

class _GhanaNetworkStatusBannerState extends State<GhanaNetworkStatusBanner>
    with WidgetsBindingObserver {
  GhanaReachabilityMonitor? _monitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createMonitor();
  }

  @override
  void didUpdateWidget(covariant GhanaNetworkStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.probe != widget.probe ||
        oldWidget.connectivitySource != widget.connectivitySource ||
        oldWidget.checkInterval != widget.checkInterval) {
      _monitor?.dispose();
      _createMonitor();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final monitor = _monitor;
      if (monitor != null) {
        unawaited(monitor.checkNow());
      }
    }
  }

  void _createMonitor() {
    if (!AsmApiBaseUrl.isUsable(widget.baseUrl)) {
      _monitor = null;
      return;
    }

    final monitor = GhanaReachabilityMonitor(
      reachability: GhanaApiReachability(
        baseUrl: widget.baseUrl,
        probe: widget.probe,
      ),
      connectivitySource: widget.connectivitySource,
      checkInterval: widget.checkInterval,
    );
    _monitor = monitor;
    unawaited(monitor.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monitor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitor = _monitor;
    if (monitor == null) {
      return GhanaNetworkStateScope(
        state: GhanaNetworkState.checking,
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: monitor,
      child: widget.child,
      builder: (context, child) {
        final state = monitor.state;
        return GhanaNetworkStateScope(
          state: state,
          child: Column(
            children: [
              if (state.isOffline)
                Material(
                  key: const Key('ghana-network-offline-banner'),
                  color: const Color(0xFFFFE8B2),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.signal_wifi_connected_no_internet_4_outlined,
                            color: Color(0xFF5A3A00),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.offlineMessage,
                              style: const TextStyle(
                                color: Color(0xFF5A3A00),
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: child!),
            ],
          ),
        );
      },
    );
  }
}

final class GhanaRequestPolicy {
  const GhanaRequestPolicy._();

  static const connectTimeout = Duration(seconds: 15);
  static const sendTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 15);
  static const requestTimeout = Duration(seconds: 15);
  static const reachabilityTimeout = Duration(seconds: 4);
  static const reachabilityCheckInterval = Duration(seconds: 15);
  static const retryBackoffs = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];
  static const maxAttempts = 4;
  static const manualRetryMessage =
      'Connection is still unstable. Please try again.';

  static const gzipHeaders = <String, String>{'Accept-Encoding': 'gzip'};

  static Map<String, String> headersFor(
    Map<String, String>? additionalHeaders,
  ) {
    final headers = <String, String>{...?additionalHeaders};
    headers.putIfAbsent('Accept-Encoding', () => 'gzip');
    return headers;
  }

  static bool isSafeToRetry(String method, Map<String, String> headers) {
    final normalizedMethod = method.trim().toUpperCase();
    if (normalizedMethod == 'GET' || normalizedMethod == 'HEAD') {
      return true;
    }

    return headers.entries.any(
      (entry) =>
          entry.key.toLowerCase() == 'idempotency-key' &&
          entry.value.trim().isNotEmpty,
    );
  }

  static bool shouldRetry<T>(ApiResponse<T> response) {
    final error = response.error;
    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout) {
      return true;
    }

    return const <int>{502, 503, 504}.contains(response.statusCode);
  }

  static Duration backoffForRetry(int retryNumber) {
    if (retryNumber < 1 || retryNumber > retryBackoffs.length) {
      throw RangeError.range(
        retryNumber,
        1,
        retryBackoffs.length,
        'retryNumber',
      );
    }

    return retryBackoffs[retryNumber - 1];
  }
}

final class GhanaRetryPolicy {
  const GhanaRetryPolicy({this.delay});

  final Future<void> Function(Duration duration)? delay;

  Future<ApiResponse<T>> execute<T>({
    required bool safeToRetry,
    required Future<ApiResponse<T>> Function() operation,
  }) async {
    for (
      var attempt = 0;
      attempt < GhanaRequestPolicy.maxAttempts;
      attempt += 1
    ) {
      final response = await operation();
      final retriesExhausted =
          attempt >= GhanaRequestPolicy.retryBackoffs.length;
      if (retriesExhausted ||
          !safeToRetry ||
          !GhanaRequestPolicy.shouldRetry(response)) {
        return response;
      }

      final wait = GhanaRequestPolicy.retryBackoffs[attempt];
      final customDelay = delay;
      if (customDelay == null) {
        await Future<void>.delayed(wait);
      } else {
        await customDelay(wait);
      }
    }

    throw StateError('Ghana retry policy exhausted unexpectedly.');
  }
}

class GhanaResilientApiClient extends AsmApiClient {
  GhanaResilientApiClient({
    required super.baseUrl,
    super.tokenProvider,
    this._retryPolicy = const GhanaRetryPolicy(),
  }) : super(
         connectTimeout: GhanaRequestPolicy.connectTimeout,
         sendTimeout: GhanaRequestPolicy.sendTimeout,
         receiveTimeout: GhanaRequestPolicy.receiveTimeout,
         requestTimeout: GhanaRequestPolicy.requestTimeout,
       );

  final GhanaRetryPolicy _retryPolicy;

  @override
  Future<ApiResponse<T>> request<T>({
    required String method,
    required String path,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    JsonDecoder<T>? decoder,
  }) {
    final requestHeaders = GhanaRequestPolicy.headersFor(headers);
    final safeToRetry = GhanaRequestPolicy.isSafeToRetry(
      method,
      requestHeaders,
    );

    return _retryPolicy.execute<T>(
      safeToRetry: safeToRetry,
      operation: () => super.request<T>(
        method: method,
        path: path,
        data: data,
        queryParameters: queryParameters,
        headers: requestHeaders,
        decoder: decoder,
      ),
    );
  }
}
