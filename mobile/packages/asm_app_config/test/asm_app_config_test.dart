import 'package:asm_app_config/asm_app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ghana market configuration', () {
    test('contains the exact permanent Accra market values', () {
      const market = MarketConfig.ghanaAccra;

      expect(market.marketCode, 'gh-accra');
      expect(market.countryCode, 'GH');
      expect(market.countryName, 'Ghana');
      expect(market.city, 'Accra');
      expect(market.currencyCode, 'GHS');
      expect(market.currencySymbol, 'GH₵');
      expect(market.localeTag, 'en-GH');
      expect(market.timeZone, 'Africa/Accra');
      expect(market.phonePrefix, '+233');
      expect(market.operatingModel, OperatingModel.controlledPilot);
    });

    test('keeps the geographic code separate from operating status', () {
      const market = MarketConfig.ghanaAccra;

      expect(market.marketCode, 'gh-accra');
      expect(market.marketCode, isNot(contains('pilot')));
      expect(market.operatingModel, OperatingModel.controlledPilot);
    });
  });

  group('capabilities', () {
    test('all capabilities default to disabled', () {
      const capabilities = CapabilityConfig();

      expect(capabilities.publicRegistration, isFalse);
      expect(capabilities.liveMaps, isFalse);
      expect(capabilities.bookingSubmission, isFalse);
      expect(capabilities.payments, isFalse);
      expect(capabilities.wallets, isFalse);
      expect(capabilities.automatedMatching, isFalse);
    });

    test('staging and production never enable capabilities', () {
      for (final value in ['staging', 'production']) {
        final config = AsmAppConfigLoader.fromValues(environmentValue: value);

        expect(config.capabilities.publicRegistration, isFalse);
        expect(config.capabilities.liveMaps, isFalse);
        expect(config.capabilities.bookingSubmission, isFalse);
        expect(config.capabilities.payments, isFalse);
        expect(config.capabilities.wallets, isFalse);
        expect(config.capabilities.automatedMatching, isFalse);
      }
    });
  });

  group('disabled mobile integration dependencies', () {
    test('keeps CC4A and CC4B disabled by default', () {
      const dependencies = MobileIntegrationDependencyConfig();

      expect(dependencies.mobileAuthApiEnabled, isFalse);
      expect(dependencies.rideRequestApiEnabled, isFalse);
    });

    test('exposes only pending dependency labels', () {
      const dependencies = MobileIntegrationDependencyConfig();

      expect(
        dependencies.mobileAuthApiDependencyLabel,
        'CC4A Mobile auth API pending',
      );
      expect(
        dependencies.rideRequestApiDependencyLabel,
        'CC4B Ride request API pending',
      );
      expect(dependencies.dependencyLabels, [
        'CC4A Mobile auth API pending',
        'CC4B Ride request API pending',
      ]);
    });

    test('does not expose endpoint URLs, tokens, or secrets', () {
      const dependencies = MobileIntegrationDependencyConfig();
      final exposedText = dependencies.dependencyLabels.join(' ').toLowerCase();

      expect(exposedText, isNot(contains('://')));
      expect(exposedText, isNot(contains('/')));
      expect(exposedText, isNot(contains('api/auth')));
      expect(exposedText, isNot(contains('token')));
      expect(exposedText, isNot(contains('secret')));
    });

    test('loads disabled mobile dependencies in the app config', () {
      final config = AsmAppConfigLoader.fromValues();

      expect(
        config.mobileIntegrationDependencies.mobileAuthApiEnabled,
        isFalse,
      );
      expect(
        config.mobileIntegrationDependencies.rideRequestApiEnabled,
        isFalse,
      );
      expect(
        config.mobileIntegrationDependencies.mobileAuthApiDependencyLabel,
        'CC4A Mobile auth API pending',
      );
      expect(
        config.mobileIntegrationDependencies.rideRequestApiDependencyLabel,
        'CC4B Ride request API pending',
      );
    });
  });

  group('runtime loading', () {
    test('parses every supported runtime environment', () {
      expect(
        RuntimeEnvironmentResolver.resolve('local'),
        RuntimeEnvironment.local,
      );
      expect(
        RuntimeEnvironmentResolver.resolve('development'),
        RuntimeEnvironment.development,
      );
      expect(
        RuntimeEnvironmentResolver.resolve('staging'),
        RuntimeEnvironment.staging,
      );
      expect(
        RuntimeEnvironmentResolver.resolve('production'),
        RuntimeEnvironment.production,
      );
    });

    test('uses safe local and Ghana defaults', () {
      final config = AsmAppConfigLoader.fromValues();
      final compileTimeConfig = AsmAppConfigLoader.fromCompileTimeEnvironment();

      expect(config.environment, RuntimeEnvironment.local);
      expect(config.market.marketCode, 'gh-accra');
      expect(compileTimeConfig.environment, RuntimeEnvironment.local);
      expect(compileTimeConfig.market, same(MarketConfig.ghanaAccra));
      expect(AsmAppConfigLoader.defaultEnvironmentValue, 'local');
      expect(AsmAppConfigLoader.defaultMarketValue, 'gh-accra');
    });

    test('rejects blank and unknown environments with stable messages', () {
      expect(
        () => RuntimeEnvironmentResolver.resolve('  '),
        throwsA(
          isA<AsmConfigurationException>().having(
            (error) => error.message,
            'message',
            'ASM_ENV must not be blank.',
          ),
        ),
      );
      expect(
        () => RuntimeEnvironmentResolver.resolve('qa'),
        throwsA(
          isA<AsmConfigurationException>().having(
            (error) => error.message,
            'message',
            'Unsupported ASM_ENV value: "qa".',
          ),
        ),
      );
    });
  });

  group('market registry', () {
    test('contains only Ghana and Accra and resolves a stable value', () {
      final registry = MarketRegistry();

      expect(registry.markets.keys, ['gh-accra']);
      expect(registry.markets.values, [MarketConfig.ghanaAccra]);
      expect(
        identical(registry.resolve('gh-accra'), registry.resolve('gh-accra')),
        isTrue,
      );
    });

    test('exposes an unmodifiable registry collection', () {
      final registry = MarketRegistry();

      expect(
        () => registry.markets['test-market'] = MarketConfig.ghanaAccra,
        throwsUnsupportedError,
      );
      expect(registry.markets.keys, ['gh-accra']);
    });

    test('rejects blank and unknown markets with stable messages', () {
      final resolver = MarketResolver();

      expect(
        () => resolver.resolve('  '),
        throwsA(
          isA<AsmConfigurationException>().having(
            (error) => error.message,
            'message',
            'ASM_MARKET must not be blank.',
          ),
        ),
      );
      expect(
        () => resolver.resolve('unknown-market'),
        throwsA(
          isA<AsmConfigurationException>().having(
            (error) => error.message,
            'message',
            'Unsupported ASM_MARKET value: "unknown-market".',
          ),
        ),
      );
    });
  });
}
