import 'dart:convert';

import 'package:asm_auth/asm_auth.dart';

import 'driver_trip_action_gateway.dart';

const driverAccessTokenRefreshThreshold = Duration(seconds: 60);

final class DriverAccessTokenResolution {
  const DriverAccessTokenResolution({
    required this.accessToken,
    required this.refreshed,
  });

  final String accessToken;
  final bool refreshed;
}

final class DriverAccessTokenRefreshException implements Exception {
  const DriverAccessTokenRefreshException();
}

final class DriverAccessTokenRefreshGuard {
  DriverAccessTokenRefreshGuard({
    required this.tokenStore,
    this.refreshAccessToken,
    DateTime Function()? utcNow,
    this.refreshThreshold = driverAccessTokenRefreshThreshold,
  }) : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final AuthTokenStore tokenStore;
  final DriverAccessTokenRefresh? refreshAccessToken;
  final DateTime Function() _utcNow;
  final Duration refreshThreshold;

  Future<DriverAccessTokenResolution> resolve({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final storedAccessToken = await _readAccessToken();

      if (storedAccessToken != null &&
          _accessTokenRemainsValid(storedAccessToken)) {
        return DriverAccessTokenResolution(
          accessToken: storedAccessToken,
          refreshed: false,
        );
      }
    }

    return _refresh();
  }

  Future<DriverAccessTokenResolution> _refresh() async {
    final refresh = refreshAccessToken;

    if (refresh == null) {
      throw const DriverAccessTokenRefreshException();
    }

    DriverTokenRefreshOutcome outcome;

    try {
      outcome = await refresh();
    } on Object {
      throw const DriverAccessTokenRefreshException();
    }

    if (outcome != DriverTokenRefreshOutcome.refreshed) {
      throw const DriverAccessTokenRefreshException();
    }

    final refreshedAccessToken = await _readAccessToken();

    if (refreshedAccessToken == null) {
      throw const DriverAccessTokenRefreshException();
    }

    return DriverAccessTokenResolution(
      accessToken: refreshedAccessToken,
      refreshed: true,
    );
  }

  Future<String?> _readAccessToken() async {
    try {
      final token = (await tokenStore.readAccessToken())?.trim();
      return token == null || token.isEmpty ? null : token;
    } on Object {
      return null;
    }
  }

  bool _accessTokenRemainsValid(String accessToken) {
    try {
      final segments = accessToken.split('.');

      if (segments.length != 3) {
        return false;
      }

      final payloadBytes = base64Url.decode(base64Url.normalize(segments[1]));
      final payload = jsonDecode(utf8.decode(payloadBytes));

      if (payload is! Map) {
        return false;
      }

      final expiryClaim = payload['exp'];

      if (expiryClaim is! num || !expiryClaim.isFinite) {
        return false;
      }

      final expiry = DateTime.fromMillisecondsSinceEpoch(
        (expiryClaim * Duration.millisecondsPerSecond).round(),
        isUtc: true,
      );
      final refreshBoundary = _utcNow().toUtc().add(refreshThreshold);

      return expiry.isAfter(refreshBoundary);
    } on Object {
      return false;
    }
  }
}
