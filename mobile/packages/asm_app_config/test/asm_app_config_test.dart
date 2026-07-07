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

    test('orders Ghana Accra supported payment methods and default safely', () {
      const market = MarketConfig.ghanaAccra;

      expect(market.supportedPaymentMethods, [
        PaymentMethod.mtnMomo,
        PaymentMethod.telecelCash,
        PaymentMethod.airteltigoMoney,
      ]);
      expect(market.defaultPaymentMethod, PaymentMethod.mtnMomo);
      expect(market.defaultPaymentMethodIsSupported, isTrue);
      expect(
        market.supportedPaymentMethods.contains(market.defaultPaymentMethod),
        isTrue,
      );
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

    test('M3A keeps future backend-dependent capabilities disabled', () {
      final defaultConfig = AsmAppConfigLoader.fromValues();
      expect(defaultConfig.capabilities.publicRegistration, isFalse);
      expect(defaultConfig.capabilities.liveMaps, isFalse);
      expect(defaultConfig.capabilities.bookingSubmission, isFalse);
      expect(defaultConfig.capabilities.payments, isFalse);
      expect(defaultConfig.capabilities.wallets, isFalse);
      expect(defaultConfig.capabilities.automatedMatching, isFalse);
      expect(
        defaultConfig.mobileIntegrationDependencies.mobileAuthApiEnabled,
        isFalse,
      );
      expect(
        defaultConfig.mobileIntegrationDependencies.rideRequestApiEnabled,
        isFalse,
      );

      for (final environment in <String>[
        'local',
        'development',
        'staging',
        'production',
      ]) {
        final config = AsmAppConfigLoader.fromValues(
          environmentValue: environment,
        );

        expect(config.capabilities.publicRegistration, isFalse);
        expect(config.capabilities.liveMaps, isFalse);
        expect(config.capabilities.bookingSubmission, isFalse);
        expect(config.capabilities.payments, isFalse);
        expect(config.capabilities.wallets, isFalse);
        expect(config.capabilities.automatedMatching, isFalse);
        expect(
          config.mobileIntegrationDependencies.mobileAuthApiEnabled,
          isFalse,
        );
        expect(
          config.mobileIntegrationDependencies.rideRequestApiEnabled,
          isFalse,
        );
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
      expect(config.localQaEnabled, isFalse);
      expect(compileTimeConfig.localQaEnabled, isA<bool>());
      expect(
        compileTimeConfig.localQaEnabled,
        LocalQaFlagResolver.resolve(
          const String.fromEnvironment(LocalQaFlagResolver.environmentKey),
        ),
      );
    });

    test('parses explicit local QA true values only', () {
      for (final value in ['true', 'TRUE', '1', 'yes']) {
        expect(
          AsmAppConfigLoader.fromValues(localQaValue: value).localQaEnabled,
          isTrue,
          reason: value,
        );
        expect(LocalQaFlagResolver.resolve(value), isTrue, reason: value);
      }
    });

    test(
      'treats missing, empty, false, and invalid local QA values as disabled',
      () {
        for (final value in <String?>[
          null,
          '',
          ' ',
          'false',
          'FALSE',
          '0',
          'no',
          'enabled',
          'True',
          'YES',
        ]) {
          expect(
            AsmAppConfigLoader.fromValues(localQaValue: value).localQaEnabled,
            isFalse,
            reason: '$value',
          );
          expect(LocalQaFlagResolver.resolve(value), isFalse, reason: '$value');
        }
      },
    );

    test('exposes stable local QA dart-define key', () {
      expect(LocalQaFlagResolver.environmentKey, 'ASM_ENABLE_LOCAL_QA');
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
