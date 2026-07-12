import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

abstract interface class PassengerRideRequestHistoryRepository {
  Future<List<PassengerRideRequestRecord>> fetchRequests();

  Future<PassengerRideRequestRecord> fetchRequest(String requestReference);
}

abstract interface class PassengerRideRequestHistoryApiGateway {
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder});
}

class AsmPassengerRideRequestHistoryApiGateway
    implements PassengerRideRequestHistoryApiGateway {
  const AsmPassengerRideRequestHistoryApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) {
    return client.get<T>(path, decoder: decoder);
  }
}

class PassengerRideRequestRecord {
  const PassengerRideRequestRecord({
    required this.requestReference,
    required this.status,
    required this.pickupLocation,
    required this.destination,
    required this.passengerCount,
    required this.createdAt,
    required this.updatedAt,
    required this.hasMobileReceipt,
    required this.tripCreated,
    this.requestedPickupTime,
    this.latestStaffState,
    this.controlCenterMessage,
  });

  final String requestReference;
  final String status;
  final String pickupLocation;
  final String destination;
  final int passengerCount;
  final DateTime? requestedPickupTime;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool hasMobileReceipt;
  final bool tripCreated;
  final String? latestStaffState;
  final String? controlCenterMessage;

  factory PassengerRideRequestRecord.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Ride request history item was not a JSON object.',
      );
    }

    final map = json.map((key, value) => MapEntry('$key', value));

    return PassengerRideRequestRecord(
      requestReference: _requiredString(map, 'request_reference'),
      status: _requiredString(map, 'status'),
      pickupLocation: _requiredString(map, 'pickup_location'),
      destination: _requiredString(map, 'destination'),
      passengerCount: _requiredInt(map, 'passenger_count'),
      requestedPickupTime: _optionalDateTime(map, 'requested_pickup_time'),
      createdAt: _optionalDateTime(map, 'created_at'),
      updatedAt: _optionalDateTime(map, 'updated_at'),
      hasMobileReceipt: _optionalBool(map, 'has_mobile_receipt'),
      tripCreated: _optionalBool(map, 'trip_created'),
      latestStaffState: _optionalString(map, 'latest_staff_state'),
      controlCenterMessage: _optionalString(map, 'control_center_message'),
    );
  }

  static List<PassengerRideRequestRecord> listFromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException(
        'Ride request history response was not a JSON object.',
      );
    }

    final results = json['results'];
    if (results is! List) {
      throw const FormatException(
        'Ride request history response did not include results.',
      );
    }

    return results
        .map(PassengerRideRequestRecord.fromJson)
        .toList(growable: false);
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Ride request history field $key is missing.');
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw FormatException('Ride request history field $key is missing.');
  }

  static bool _optionalBool(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is bool ? value : false;
  }

  static DateTime? _optionalDateTime(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }
}

class ApiPassengerRideRequestHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  const ApiPassengerRideRequestHistoryRepository(
    this.apiGateway, {
    required this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerRideRequestHistoryRepository.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final store = tokenStore ?? SecureAuthTokenStore();
    final connectionConfigured = AsmApiBaseUrl.isUsable(baseUrl);
    final resolvedBaseUrl = connectionConfigured
        ? baseUrl!.trim()
        : 'http://127.0.0.1:8000';

    return ApiPassengerRideRequestHistoryRepository(
      AsmPassengerRideRequestHistoryApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _HistoryTokenProvider(store),
        ),
      ),
      tokenStore: store,
      authService: connectionConfigured
          ? AuthService.withApiClient(
              client: AsmApiClient(baseUrl: resolvedBaseUrl),
              tokenStore: store,
            )
          : null,
      connectionConfigured: connectionConfigured,
    );
  }

  static const listPath = '/api/rides/requests/';

  final PassengerRideRequestHistoryApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final AuthService? authService;
  final bool connectionConfigured;

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return _get<List<PassengerRideRequestRecord>>(
      listPath,
      PassengerRideRequestRecord.listFromJson,
    );
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    final normalized = requestReference.trim();
    if (normalized.isEmpty) {
      throw const PassengerRideRequestHistoryException.unknown();
    }

    return _get<PassengerRideRequestRecord>(
      '$listPath${Uri.encodeComponent(normalized)}/',
      PassengerRideRequestRecord.fromJson,
    );
  }

  Future<T> _get<T>(String path, JsonDecoder<T> decoder) async {
    final accessToken = (await tokenStore.readAccessToken())?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerRideRequestHistoryException.sessionExpired();
    }

    if (!connectionConfigured) {
      throw const PassengerRideRequestHistoryException.connectionNotConfigured();
    }

    final response = await apiGateway.get<T>(path, decoder: decoder);

    if (response.isSuccess && response.data != null) {
      return response.data as T;
    }

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        throw const PassengerRideRequestHistoryException.sessionExpired();
      }

      final retryResponse = await apiGateway.get<T>(path, decoder: decoder);

      if (retryResponse.isSuccess && retryResponse.data != null) {
        return retryResponse.data as T;
      }

      if (retryResponse.statusCode == 401) {
        await tokenStore.clearTokens();
      }

      throw PassengerRideRequestHistoryException.fromResponse(retryResponse);
    }

    throw PassengerRideRequestHistoryException.fromResponse(response);
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = (await tokenStore.readRefreshToken())?.trim();

    final service = authService;

    if (refreshToken == null || refreshToken.isEmpty || service == null) {
      await tokenStore.clearTokens();
      return false;
    }

    try {
      final state = await service.refresh();
      if (state.isAuthenticated) {
        return true;
      }
    } on Object {
      // The user-facing state below remains intentionally generic.
    }

    await tokenStore.clearTokens();
    return false;
  }
}

class UnavailablePassengerRideRequestHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  const UnavailablePassengerRideRequestHistoryRepository();

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() {
    return Future<List<PassengerRideRequestRecord>>.error(
      const PassengerRideRequestHistoryException.connectionNotConfigured(),
    );
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.connectionNotConfigured(),
    );
  }
}

class EmptyPassengerRideRequestHistoryRepository
    implements PassengerRideRequestHistoryRepository {
  const EmptyPassengerRideRequestHistoryRepository();

  @override
  Future<List<PassengerRideRequestRecord>> fetchRequests() async {
    return const <PassengerRideRequestRecord>[];
  }

  @override
  Future<PassengerRideRequestRecord> fetchRequest(String requestReference) {
    return Future<PassengerRideRequestRecord>.error(
      const PassengerRideRequestHistoryException.notFound(),
    );
  }
}

class PassengerRideRequestHistoryException implements Exception {
  const PassengerRideRequestHistoryException(
    this.message, {
    this.requiresSignIn = false,
  });

  const PassengerRideRequestHistoryException.sessionExpired()
    : message = sessionExpiredMessage,
      requiresSignIn = true;

  const PassengerRideRequestHistoryException.connectionNotConfigured()
    : message = AsmApiClient.connectionNotConfiguredMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.network()
    : message = networkMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.server()
    : message = serverMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.notFound()
    : message = notFoundMessage,
      requiresSignIn = false;

  const PassengerRideRequestHistoryException.unknown()
    : message = unknownMessage,
      requiresSignIn = false;

  static const sessionExpiredMessage =
      'Your session has expired. Please sign in again.';
  static const networkMessage =
      'Cannot reach the server. Check your connection and try again.';
  static const serverMessage =
      'Service is temporarily unavailable. Please try again later.';
  static const notFoundMessage = 'This ride request could not be found.';
  static const passengerRequiredMessage = 'Passenger account required.';
  static const unknownMessage = 'Something went wrong. Please try again.';

  final String message;
  final bool requiresSignIn;

  static PassengerRideRequestHistoryException fromResponse<T>(
    ApiResponse<T> response,
  ) {
    final error = response.error;
    final statusCode = response.statusCode;

    if (statusCode == 401) {
      return const PassengerRideRequestHistoryException.sessionExpired();
    }

    if (statusCode == 403) {
      return const PassengerRideRequestHistoryException(
        passengerRequiredMessage,
      );
    }

    if (statusCode == 404) {
      return const PassengerRideRequestHistoryException.notFound();
    }

    if (error?.type == AsmApiExceptionType.network ||
        error?.type == AsmApiExceptionType.timeout) {
      return const PassengerRideRequestHistoryException.network();
    }

    if (statusCode == 503 || error?.type == AsmApiExceptionType.server) {
      return const PassengerRideRequestHistoryException.server();
    }

    return const PassengerRideRequestHistoryException.unknown();
  }

  @override
  String toString() => message;
}

class PassengerRideRequestHistoryPage extends StatefulWidget {
  const PassengerRideRequestHistoryPage({
    required this.repository,
    this.onSignInRequired,
    this.onBookRide,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final VoidCallback? onSignInRequired;
  final VoidCallback? onBookRide;

  @override
  State<PassengerRideRequestHistoryPage> createState() =>
      _PassengerRideRequestHistoryPageState();
}

class _PassengerRideRequestHistoryPageState
    extends State<PassengerRideRequestHistoryPage> {
  bool _loading = true;
  List<PassengerRideRequestRecord> _records =
      const <PassengerRideRequestRecord>[];
  PassengerRideRequestHistoryException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final records = List<PassengerRideRequestRecord>.of(
        await widget.repository.fetchRequests(),
      );
      records.sort((left, right) {
        final leftCreatedAt = left.createdAt;
        final rightCreatedAt = right.createdAt;

        if (leftCreatedAt == null && rightCreatedAt == null) {
          return 0;
        }
        if (leftCreatedAt == null) {
          return 1;
        }
        if (rightCreatedAt == null) {
          return -1;
        }

        return rightCreatedAt.compareTo(leftCreatedAt);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _records = records;
        _error = null;
      });
    } on PassengerRideRequestHistoryException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _records = const <PassengerRideRequestRecord>[];
        _error = error;
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _records = const <PassengerRideRequestRecord>[];
        _error = const PassengerRideRequestHistoryException.unknown();
      });
    }
  }

  Future<void> _openDetail(PassengerRideRequestRecord record) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PassengerRideRequestDetailPage(
          repository: widget.repository,
          requestReference: record.requestReference,
          onSignInRequired: widget.onSignInRequired,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ride Requests'),
        actions: [
          IconButton(
            key: const Key('ride-request-history-refresh'),
            onPressed: _loading ? null : () => _load(),
            tooltip: 'Refresh requests',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        key: Key('ride-request-history-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final error = _error;
    if (error != null) {
      return _HistoryErrorState(
        error: error,
        onRetry: _load,
        onSignInRequired: widget.onSignInRequired,
      );
    }

    if (_records.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: ListView(
          key: const Key('ride-request-history-empty'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AsmSpacing.space24),
          children: [
            const SizedBox(height: 120),
            const Icon(Icons.receipt_long_outlined, size: 56),
            const SizedBox(height: AsmSpacing.space16),
            const Text(
              'No ride requests yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AsmSpacing.space8),
            const Text(
              'Your ride requests will appear here after you book.',
              textAlign: TextAlign.center,
            ),
            if (widget.onBookRide != null) ...[
              const SizedBox(height: AsmSpacing.space24),
              Center(
                child: FilledButton.icon(
                  key: const Key('empty-history-book-ride'),
                  onPressed: widget.onBookRide,
                  icon: const Icon(Icons.add_road_outlined),
                  label: const Text('Book a ride'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showLoading: false),
      child: ListView.separated(
        key: const Key('ride-request-history-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AsmSpacing.space16),
        itemCount: _records.length,
        separatorBuilder: (_, _) => const SizedBox(height: AsmSpacing.space12),
        itemBuilder: (context, index) {
          final record = _records[index];

          return _RideRequestCard(
            record: record,
            onTap: () => _openDetail(record),
          );
        },
      ),
    );
  }
}

class _RideRequestCard extends StatelessWidget {
  const _RideRequestCard({required this.record, required this.onTap});

  final PassengerRideRequestRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusMessage = _safeStatusMessage(
      record.status,
      preferredMessage: record.latestStaffState,
    );

    return Card(
      key: ValueKey<String>('ride-request-${record.requestReference}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AsmSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      record.requestReference,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: AsmSpacing.space8),
                  _StatusChip(status: record.status),
                ],
              ),
              const SizedBox(height: AsmSpacing.space12),
              Text(
                record.pickupLocation,
                key: ValueKey<String>('pickup-${record.requestReference}'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AsmSpacing.space4),
                child: Icon(Icons.arrow_downward, size: 18),
              ),
              Text(
                record.destination,
                key: ValueKey<String>('destination-${record.requestReference}'),
              ),
              const SizedBox(height: AsmSpacing.space12),
              Text(
                statusMessage,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AsmSpacing.space8),
              Text(
                'Created ${_formatDateTime(record.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (record.hasMobileReceipt) ...[
                const SizedBox(height: AsmSpacing.space8),
                const Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 18),
                    SizedBox(width: AsmSpacing.space4),
                    Expanded(child: Text('Request received')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PassengerRideRequestDetailPage extends StatefulWidget {
  const PassengerRideRequestDetailPage({
    required this.repository,
    required this.requestReference,
    this.onSignInRequired,
    super.key,
  });

  final PassengerRideRequestHistoryRepository repository;
  final String requestReference;
  final VoidCallback? onSignInRequired;

  @override
  State<PassengerRideRequestDetailPage> createState() =>
      _PassengerRideRequestDetailPageState();
}

class _PassengerRideRequestDetailPageState
    extends State<PassengerRideRequestDetailPage> {
  bool _loading = true;
  PassengerRideRequestRecord? _record;
  PassengerRideRequestHistoryException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final record = await widget.repository.fetchRequest(
        widget.requestReference,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _record = record;
        _error = null;
      });
    } on PassengerRideRequestHistoryException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _record = null;
        _error = error;
      });
    } on Object {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _record = null;
        _error = const PassengerRideRequestHistoryException.unknown();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Request Detail')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('ride-request-detail-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final error = _error;
    if (error != null) {
      return _HistoryErrorState(
        error: error,
        onRetry: _load,
        onSignInRequired: widget.onSignInRequired,
      );
    }

    final record = _record;
    if (record == null) {
      return const SizedBox.shrink();
    }

    final controlCenterMessage = _safeStatusMessage(
      record.status,
      preferredMessage: record.controlCenterMessage,
    );

    return ListView(
      key: const Key('ride-request-detail-loaded'),
      padding: const EdgeInsets.all(AsmSpacing.space16),
      children: [
        _StatusChip(status: record.status),
        const SizedBox(height: AsmSpacing.space16),
        _DetailRow(label: 'Request reference', value: record.requestReference),
        _DetailRow(label: 'Pickup', value: record.pickupLocation),
        _DetailRow(label: 'Destination', value: record.destination),
        _DetailRow(label: 'Passengers', value: '${record.passengerCount}'),
        if (record.requestedPickupTime != null)
          _DetailRow(
            label: 'Requested pickup time',
            value: _formatDateTime(record.requestedPickupTime),
          ),
        _DetailRow(label: 'Created', value: _formatDateTime(record.createdAt)),
        _DetailRow(label: 'Updated', value: _formatDateTime(record.updatedAt)),
        _DetailRow(
          label: 'Request receipt',
          value: record.hasMobileReceipt ? 'Confirmed' : 'Not available',
        ),
        _DetailRow(
          label: 'Trip record',
          value: record.tripCreated
              ? 'Converted into trip record'
              : 'Not yet converted into a trip',
        ),
        const SizedBox(height: AsmSpacing.space8),
        Card(
          key: const Key('ride-request-control-center-message'),
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ALANTEH update',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AsmSpacing.space8),
                Text(controlCenterMessage),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      key: ValueKey<String>('ride-request-status-$status'),
      label: Text(_statusLabel(status)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AsmSpacing.space4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState({
    required this.error,
    required this.onRetry,
    this.onSignInRequired,
  });

  final PassengerRideRequestHistoryException error;
  final Future<void> Function() onRetry;
  final VoidCallback? onSignInRequired;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: Key(
        error.requiresSignIn
            ? 'ride-request-history-session-expired'
            : 'ride-request-history-error',
      ),
      child: Padding(
        padding: const EdgeInsets.all(AsmSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error.requiresSignIn
                  ? Icons.lock_clock_outlined
                  : Icons.error_outline,
              size: 52,
            ),
            const SizedBox(height: AsmSpacing.space16),
            Text(
              error.requiresSignIn
                  ? 'Session expired'
                  : 'Could not load requests',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(error.message, textAlign: TextAlign.center),
            const SizedBox(height: AsmSpacing.space16),
            if (error.requiresSignIn && onSignInRequired != null)
              FilledButton(
                key: const Key('ride-request-history-sign-in-again'),
                onPressed: onSignInRequired,
                child: const Text('Sign in again'),
              )
            else
              FilledButton.icon(
                key: const Key('ride-request-history-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}

String _safeStatusMessage(String status, {String? preferredMessage}) {
  final safePreferredMessage = preferredMessage?.trim();
  if (safePreferredMessage != null && safePreferredMessage.isNotEmpty) {
    final lower = safePreferredMessage.toLowerCase();
    final mentionsInternalOps = RegExp(
      r'control\s+center',
      caseSensitive: false,
    ).hasMatch(safePreferredMessage);
    final isPassengerAppReceipt = lower.contains(
      'passenger app request received',
    );
    final isMobileReceiptMessage = lower.contains('mobile receipt confirmed');

    if (isPassengerAppReceipt || isMobileReceiptMessage) {
      return 'Request received.';
    }

    if (mentionsInternalOps) {
      return safePreferredMessage.replaceAll(
        RegExp(r'control\s+center', caseSensitive: false),
        'ALANTEH',
      );
    }

    return safePreferredMessage;
  }

  return switch (status.trim().toLowerCase()) {
    'requested' => 'Request received.',
    'under_review' => 'Being reviewed.',
    'accepted' || 'approved' => 'Accepted for trip preparation.',
    'rejected' || 'declined' => 'Could not be accepted.',
    'cancelled' || 'canceled' => 'Cancelled.',
    'trip_created' => 'Trip record created.',
    _ => 'Request update available.',
  };
}

String _statusLabel(String status) {
  return switch (status.trim().toLowerCase()) {
    'requested' => 'Received by ALANTEH',
    'under_review' => 'Being reviewed',
    'accepted' || 'approved' => 'Accepted for trip preparation',
    'rejected' || 'declined' => 'Could not be accepted',
    'cancelled' || 'canceled' => 'Cancelled',
    'trip_created' => 'Trip record created',
    _ => 'Request update',
  };
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }

  final local = value.toLocal();

  String twoDigits(int number) {
    return number.toString().padLeft(2, '0');
  }

  return '${local.year}-'
      '${twoDigits(local.month)}-'
      '${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:'
      '${twoDigits(local.minute)}';
}

class _HistoryTokenProvider implements TokenProvider {
  const _HistoryTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() {
    return tokenStore.readAccessToken();
  }
}
