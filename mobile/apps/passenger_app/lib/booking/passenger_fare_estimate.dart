import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

abstract interface class PassengerFareEstimateRepository {
  Future<PassengerBookingFareEstimate> fetchEstimate(double tripKilometres);
}

abstract interface class PassengerFareEstimateApiGateway {
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  });
}

final class AsmPassengerFareEstimateApiGateway
    implements PassengerFareEstimateApiGateway {
  const AsmPassengerFareEstimateApiGateway(this.client);

  final AsmApiClient client;

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  }) {
    return client.get<T>(
      path,
      queryParameters: queryParameters,
      decoder: decoder,
    );
  }
}

final class PassengerBookingFareEstimate {
  const PassengerBookingFareEstimate({
    required this.currency,
    required this.tripKilometres,
    required this.pickupKilometres,
    required this.tripRate,
    required this.tripFare,
    required this.pickupFee,
    required this.estimatedTotal,
    required this.minimumFare,
    this.currencySymbol,
  });

  final String currency;
  final String? currencySymbol;
  final double tripKilometres;
  final double pickupKilometres;
  final double tripRate;
  final double tripFare;
  final double pickupFee;
  final double estimatedTotal;
  final double minimumFare;

  String get displayCurrency {
    final symbol = currencySymbol?.trim();
    if (symbol != null && symbol.isNotEmpty) {
      return symbol;
    }

    return switch (currency.trim().toUpperCase()) {
      'GHS' => 'GH₵',
      final code => '$code ',
    };
  }

  String money(double value) {
    return '$displayCurrency${value.toStringAsFixed(2)}';
  }

  String get tripKilometresDisplay => tripKilometres.toStringAsFixed(1);

  factory PassengerBookingFareEstimate.fromJson(Object? json) {
    final root = _jsonMap(json, label: 'Fare estimate');
    final data = root['data'];
    final dataMap = data is Map
        ? _jsonMap(data, label: 'Fare estimate data')
        : root;
    final breakdown = dataMap['breakdown'];
    final payload = breakdown is Map
        ? <String, Object?>{
            ...dataMap,
            ..._jsonMap(breakdown, label: 'Fare estimate breakdown'),
          }
        : dataMap;

    final currency = _requiredString(payload, const ['currency']);
    final pickupKilometres = _requiredNumber(payload, const [
      'pickup_km',
      'pickup_distance_km',
    ]);

    if (pickupKilometres != 0) {
      throw const FormatException(
        'Booking fare estimate pickup_km must be zero.',
      );
    }

    return PassengerBookingFareEstimate(
      currency: currency,
      currencySymbol: _optionalString(payload, const [
        'currency_symbol',
        'currency_sign',
      ]),
      tripKilometres: _requiredNonNegativeNumber(payload, const [
        'trip_km',
        'trip_distance_km',
      ]),
      pickupKilometres: pickupKilometres,
      tripRate: _requiredNonNegativeNumber(payload, const [
        'trip_rate',
        'trip_rate_per_km',
        'rate_per_km',
      ]),
      tripFare: _requiredNonNegativeNumber(payload, const ['trip_fare']),
      pickupFee: _requiredNonNegativeNumber(payload, const ['pickup_fee']),
      estimatedTotal: _requiredNonNegativeNumber(payload, const [
        'estimated_total',
        'total',
        'total_fare',
      ]),
      minimumFare: _requiredNonNegativeNumber(payload, const ['minimum_fare']),
    );
  }
}

final class ApiPassengerFareEstimateRepository
    implements PassengerFareEstimateRepository {
  const ApiPassengerFareEstimateRepository(
    this.apiGateway, {
    required this.tokenStore,
    this.authService,
    this.connectionConfigured = true,
  });

  factory ApiPassengerFareEstimateRepository.withDefaultClient({
    AuthTokenStore? tokenStore,
    String? baseUrl,
  }) {
    final resolvedTokenStore = tokenStore ?? SecureAuthTokenStore();
    final configured = AsmApiBaseUrl.isUsable(baseUrl);

    if (!configured) {
      return ApiPassengerFareEstimateRepository(
        const _UnconfiguredPassengerFareEstimateApiGateway(),
        tokenStore: resolvedTokenStore,
        connectionConfigured: false,
      );
    }

    final resolvedBaseUrl = baseUrl!.trim();

    return ApiPassengerFareEstimateRepository(
      AsmPassengerFareEstimateApiGateway(
        AsmApiClient(
          baseUrl: resolvedBaseUrl,
          tokenProvider: _FareEstimateTokenProvider(resolvedTokenStore),
        ),
      ),
      tokenStore: resolvedTokenStore,
      authService: AuthService.withApiClient(
        client: AsmApiClient(baseUrl: resolvedBaseUrl),
        tokenStore: resolvedTokenStore,
      ),
    );
  }

  static const path = '/api/rides/fare-estimate/';

  final PassengerFareEstimateApiGateway apiGateway;
  final AuthTokenStore tokenStore;
  final AuthService? authService;
  final bool connectionConfigured;

  @override
  Future<PassengerBookingFareEstimate> fetchEstimate(
    double tripKilometres,
  ) async {
    if (!tripKilometres.isFinite || tripKilometres <= 0) {
      throw const PassengerFareEstimateException();
    }

    final accessToken = (await tokenStore.readAccessToken())?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      throw const PassengerFareEstimateException.sessionExpired();
    }

    if (!connectionConfigured) {
      throw const PassengerFareEstimateException();
    }

    final queryParameters = <String, dynamic>{
      'trip_km': tripKilometres,
      'pickup_km': 0,
    };

    final response = await _request(queryParameters);

    if (response.isSuccess && response.data != null) {
      return response.data!;
    }

    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessToken();

      if (!refreshed) {
        throw const PassengerFareEstimateException.sessionExpired();
      }

      final retryResponse = await _request(queryParameters);

      if (retryResponse.isSuccess && retryResponse.data != null) {
        return retryResponse.data!;
      }

      if (retryResponse.statusCode == 401) {
        await tokenStore.clearTokens();
      }
    }

    throw const PassengerFareEstimateException();
  }

  Future<ApiResponse<PassengerBookingFareEstimate>> _request(
    Map<String, dynamic> queryParameters,
  ) {
    return apiGateway.get<PassengerBookingFareEstimate>(
      path,
      queryParameters: queryParameters,
      decoder: PassengerBookingFareEstimate.fromJson,
    );
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
      // The confirmation screen uses its safe fallback wording.
    }

    await tokenStore.clearTokens();
    return false;
  }
}

final class UnavailablePassengerFareEstimateRepository
    implements PassengerFareEstimateRepository {
  const UnavailablePassengerFareEstimateRepository();

  @override
  Future<PassengerBookingFareEstimate> fetchEstimate(double tripKilometres) {
    return Future<PassengerBookingFareEstimate>.error(
      const PassengerFareEstimateException(),
    );
  }
}

final class PassengerFareEstimateException implements Exception {
  const PassengerFareEstimateException({this.requiresSignIn = false});

  const PassengerFareEstimateException.sessionExpired() : requiresSignIn = true;

  final bool requiresSignIn;
}

class PassengerFareEstimatePanel extends StatelessWidget {
  const PassengerFareEstimatePanel({required this.estimate, super.key});

  static const fallbackText = 'Fare confirmed when driver is assigned.';
  static const finalFareText = 'Final fare confirmed when driver is assigned.';
  static const paymentText = 'Payment: MTN MoMo';

  final PassengerBookingFareEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final value = estimate;

    return Container(
      key: const Key('passenger-fare-estimate'),
      padding: const EdgeInsets.all(AsmSpacing.space16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AsmRadii.radius16),
        border: Border.all(color: AsmColors.passengerLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: AsmColors.brandDeepGreen,
              ),
              SizedBox(width: AsmSpacing.space8),
              Text(
                'Fare estimate',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: AsmSpacing.space12),
          if (value == null)
            const Text(
              fallbackText,
              key: Key('fare-estimate-fallback'),
              style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            )
          else ...[
            _FareEstimateLine(
              key: const Key('fare-estimate-trip'),
              label:
                  'Trip (${value.tripKilometresDisplay} km × ${value.money(value.tripRate)})',
              amount: value.money(value.tripFare),
            ),
            const SizedBox(height: AsmSpacing.space8),
            _FareEstimateLine(
              key: const Key('fare-estimate-pickup'),
              label: 'Pickup fee',
              amount: value.money(value.pickupFee),
            ),
            const Divider(height: AsmSpacing.space24),
            _FareEstimateLine(
              key: const Key('fare-estimate-total'),
              label: 'Estimated total',
              amount: value.money(value.estimatedTotal),
              emphasized: true,
            ),
            const SizedBox(height: AsmSpacing.space12),
            Text(
              'Minimum fare: ${value.money(value.minimumFare)}',
              key: const Key('fare-estimate-minimum'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AsmSpacing.space8),
            const Text(
              finalFareText,
              key: Key('fare-estimate-final-confirmation'),
              style: TextStyle(height: 1.35),
            ),
          ],
          const SizedBox(height: AsmSpacing.space12),
          const Text(
            paymentText,
            key: Key('fare-estimate-payment-method'),
            style: TextStyle(
              color: AsmColors.brandDeepGreen,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FareEstimateLine extends StatelessWidget {
  const _FareEstimateLine({
    required this.label,
    required this.amount,
    this.emphasized = false,
    super.key,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: AsmSpacing.space12),
        Text(amount, style: style),
      ],
    );
  }
}

Map<String, Object?> _jsonMap(Object? value, {required String label}) {
  if (value is Map<String, Object?>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  throw FormatException('$label response was not a JSON object.');
}

String _requiredString(Map<String, Object?> map, List<String> keys) {
  final value = _optionalString(map, keys);
  if (value == null) {
    throw FormatException('${keys.first} was missing.');
  }

  return value;
}

String? _optionalString(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }

  return null;
}

double _requiredNumber(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final raw = map[key];
    final parsed = switch (raw) {
      num value => value.toDouble(),
      String value => double.tryParse(value.trim()),
      _ => null,
    };

    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }

  throw FormatException('${keys.first} was missing or invalid.');
}

double _requiredNonNegativeNumber(Map<String, Object?> map, List<String> keys) {
  final value = _requiredNumber(map, keys);
  if (value < 0) {
    throw FormatException('${keys.first} cannot be negative.');
  }

  return value;
}

final class _FareEstimateTokenProvider implements TokenProvider {
  const _FareEstimateTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() {
    return tokenStore.readAccessToken();
  }
}

final class _UnconfiguredPassengerFareEstimateApiGateway
    implements PassengerFareEstimateApiGateway {
  const _UnconfiguredPassengerFareEstimateApiGateway();

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    JsonDecoder<T>? decoder,
  }) async {
    return ApiResponse<T>.apiFailure(
      const AsmApiException(
        type: AsmApiExceptionType.badResponse,
        message: AsmApiClient.connectionNotConfiguredMessage,
      ),
    );
  }
}
