import 'dart:math';

import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_auth/asm_auth.dart';

import 'booking_draft.dart';

enum BookingSubmissionStatus { idle, submitting, success, failure }

abstract interface class PassengerRideRequestSubmitter {
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  });
}

class ApiPassengerRideRequestSubmitter
    implements PassengerRideRequestSubmitter {
  const ApiPassengerRideRequestSubmitter(this.client);

  factory ApiPassengerRideRequestSubmitter.withDefaultClient({
    AuthTokenStore? tokenStore,
  }) {
    final store = tokenStore ?? SecureAuthTokenStore();
    return ApiPassengerRideRequestSubmitter(
      AsmApiClient(
        baseUrl: AsmApiClient.defaultBaseUrl,
        tokenProvider: _AuthTokenProvider(store),
      ),
    );
  }

  final AsmApiClient client;

  @override
  Future<PassengerRideRequestResult> submit(
    BookingDraft draft, {
    required String idempotencyKey,
  }) async {
    final response = await client.submitPassengerRideRequest(
      PassengerRideRequestSubmission(
        idempotencyKey: idempotencyKey,
        pickupLocation: draft.pickupDescription.value,
        destination: draft.destinationDescription.value,
        passengerCount: draft.passengerCount.value,
        assistanceNote: draft.assistanceNote?.value,
      ),
    );

    if (response.isSuccess && response.data != null) {
      return response.data!;
    }

    throw PassengerRideRequestSubmissionException.fromResponse(response);
  }
}

class PassengerRideRequestSubmissionException implements Exception {
  const PassengerRideRequestSubmissionException(this.message);

  final String message;

  factory PassengerRideRequestSubmissionException.fromResponse(
    ApiResponse<PassengerRideRequestResult> response,
  ) {
    final statusCode = response.statusCode;
    final cause = response.error?.cause;
    final detail = _detailFromCause(cause);

    if (response.isClientException) {
      return const PassengerRideRequestSubmissionException(
        'Could not send ride request.\nPlease check your connection and try again.',
      );
    }

    if (statusCode == 403) {
      return PassengerRideRequestSubmissionException(
        detail ?? 'Passenger account required.',
      );
    }

    if (statusCode == 409) {
      return PassengerRideRequestSubmissionException(
        detail ??
            'This ride request was already submitted differently. Please review and try again.',
      );
    }

    if (statusCode == 503) {
      return const PassengerRideRequestSubmissionException(
        'Ride requests are not available right now.\nPlease try again later.',
      );
    }

    if (statusCode == 400) {
      return PassengerRideRequestSubmissionException(
        detail ?? 'Please check your ride details and try again.',
      );
    }

    return PassengerRideRequestSubmissionException(
      detail ?? 'Could not send ride request.\nPlease try again.',
    );
  }

  @override
  String toString() => message;

  static String? _detailFromCause(Object? cause) {
    if (cause is Map) {
      final detail = cause['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    }
    return null;
  }
}

class PassengerRideRequestIdempotencyKey {
  PassengerRideRequestIdempotencyKey._();

  static final Random _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final parts = <String>[
      bytes.sublist(0, 4).map(hex).join(),
      bytes.sublist(4, 6).map(hex).join(),
      bytes.sublist(6, 8).map(hex).join(),
      bytes.sublist(8, 10).map(hex).join(),
      bytes.sublist(10, 16).map(hex).join(),
    ];

    return 'APP-${parts.join('-')}';
  }
}

class _AuthTokenProvider implements TokenProvider {
  const _AuthTokenProvider(this.tokenStore);

  final AuthTokenStore tokenStore;

  @override
  Future<String?> getAccessToken() => tokenStore.readAccessToken();
}
