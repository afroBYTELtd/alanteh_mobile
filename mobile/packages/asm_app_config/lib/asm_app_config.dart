enum OperatingModel { controlledPilot }

enum RuntimeEnvironment { local, development, staging, production }

enum PaymentMethod { mtnMomo, telecelCash, airteltigoMoney }

final class MarketConfig {
  const MarketConfig({
    required this.marketCode,
    required this.countryCode,
    required this.countryName,
    required this.city,
    required this.currencyCode,
    required this.currencySymbol,
    required this.localeTag,
    required this.timeZone,
    required this.phonePrefix,
    required this.operatingModel,
    required this.supportedPaymentMethods,
    required this.defaultPaymentMethod,
  });

  static const ghanaAccra = MarketConfig(
    marketCode: 'gh-accra',
    countryCode: 'GH',
    countryName: 'Ghana',
    city: 'Accra',
    currencyCode: 'GHS',
    currencySymbol: 'GH₵',
    localeTag: 'en-GH',
    timeZone: 'Africa/Accra',
    phonePrefix: '+233',
    operatingModel: OperatingModel.controlledPilot,
    supportedPaymentMethods: [
      PaymentMethod.mtnMomo,
      PaymentMethod.telecelCash,
      PaymentMethod.airteltigoMoney,
    ],
    defaultPaymentMethod: PaymentMethod.mtnMomo,
  );

  final String marketCode;
  final String countryCode;
  final String countryName;
  final String city;
  final String currencyCode;
  final String currencySymbol;
  final String localeTag;
  final String timeZone;
  final String phonePrefix;
  final OperatingModel operatingModel;
  final List<PaymentMethod> supportedPaymentMethods;
  final PaymentMethod defaultPaymentMethod;

  bool get defaultPaymentMethodIsSupported =>
      supportedPaymentMethods.contains(defaultPaymentMethod);
}

final class CapabilityConfig {
  const CapabilityConfig({
    this.publicRegistration = false,
    this.liveMaps = false,
    this.bookingSubmission = false,
    this.payments = false,
    this.wallets = false,
    this.automatedMatching = false,
  });

  final bool publicRegistration;
  final bool liveMaps;
  final bool bookingSubmission;
  final bool payments;
  final bool wallets;
  final bool automatedMatching;
}

final class MobileIntegrationDependencyConfig {
  const MobileIntegrationDependencyConfig({
    this.mobileAuthApiEnabled = false,
    this.rideRequestApiEnabled = false,
    this.mobileAuthApiDependencyLabel = cc4aMobileAuthApiPendingLabel,
    this.rideRequestApiDependencyLabel = cc4bRideRequestApiPendingLabel,
  });

  static const cc4aMobileAuthApiPendingLabel = 'CC4A Mobile auth API pending';
  static const cc4bRideRequestApiPendingLabel = 'CC4B Ride request API pending';

  final bool mobileAuthApiEnabled;
  final bool rideRequestApiEnabled;
  final String mobileAuthApiDependencyLabel;
  final String rideRequestApiDependencyLabel;

  List<String> get dependencyLabels => [
    mobileAuthApiDependencyLabel,
    rideRequestApiDependencyLabel,
  ];
}

final class AsmAppConfig {
  const AsmAppConfig({
    required this.environment,
    required this.market,
    required this.capabilities,
    this.mobileIntegrationDependencies =
        const MobileIntegrationDependencyConfig(),
    this.localQaEnabled = false,
  });

  static const localGhana = AsmAppConfig(
    environment: RuntimeEnvironment.local,
    market: MarketConfig.ghanaAccra,
    capabilities: CapabilityConfig(),
  );

  final RuntimeEnvironment environment;
  final MarketConfig market;
  final CapabilityConfig capabilities;
  final MobileIntegrationDependencyConfig mobileIntegrationDependencies;
  final bool localQaEnabled;
}

abstract final class LocalQaFlagResolver {
  static const environmentKey = 'ASM_ENABLE_LOCAL_QA';

  static bool resolve(String? value) {
    final normalized = value?.trim();
    return switch (normalized) {
      'true' || 'TRUE' || '1' || 'yes' => true,
      _ => false,
    };
  }
}

final class AsmConfigurationException implements Exception {
  const AsmConfigurationException(this.message);

  final String message;

  @override
  String toString() => 'AsmConfigurationException: $message';
}

abstract final class RuntimeEnvironmentResolver {
  static RuntimeEnvironment resolve(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const AsmConfigurationException('ASM_ENV must not be blank.');
    }

    return switch (normalized) {
      'local' => RuntimeEnvironment.local,
      'development' => RuntimeEnvironment.development,
      'staging' => RuntimeEnvironment.staging,
      'production' => RuntimeEnvironment.production,
      _ => throw AsmConfigurationException(
        'Unsupported ASM_ENV value: "$normalized".',
      ),
    };
  }
}

final class MarketRegistry {
  MarketRegistry({
    Iterable<MarketConfig> markets = const [MarketConfig.ghanaAccra],
  }) : _markets = Map.unmodifiable({
         for (final market in markets) market.marketCode: market,
       });

  static final ghanaOnly = MarketRegistry();

  final Map<String, MarketConfig> _markets;

  Map<String, MarketConfig> get markets => _markets;

  MarketConfig resolve(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const AsmConfigurationException('ASM_MARKET must not be blank.');
    }

    final market = _markets[normalized];
    if (market == null) {
      throw AsmConfigurationException(
        'Unsupported ASM_MARKET value: "$normalized".',
      );
    }
    return market;
  }
}

final class MarketResolver {
  MarketResolver({MarketRegistry? registry})
    : registry = registry ?? MarketRegistry.ghanaOnly;

  final MarketRegistry registry;

  MarketConfig resolve(String value) => registry.resolve(value);
}

abstract final class AsmAppConfigLoader {
  static const defaultEnvironmentValue = 'local';
  static const defaultMarketValue = 'gh-accra';

  static AsmAppConfig fromCompileTimeEnvironment() {
    const environmentValue = String.fromEnvironment(
      'ASM_ENV',
      defaultValue: defaultEnvironmentValue,
    );
    const marketValue = String.fromEnvironment(
      'ASM_MARKET',
      defaultValue: defaultMarketValue,
    );
    const localQaValue = String.fromEnvironment(
      LocalQaFlagResolver.environmentKey,
    );

    return fromValues(
      environmentValue: environmentValue,
      marketValue: marketValue,
      localQaValue: localQaValue,
    );
  }

  static AsmAppConfig fromValues({
    String environmentValue = defaultEnvironmentValue,
    String marketValue = defaultMarketValue,
    String? localQaValue,
    MarketRegistry? registry,
  }) {
    return AsmAppConfig(
      environment: RuntimeEnvironmentResolver.resolve(environmentValue),
      market: MarketResolver(registry: registry).resolve(marketValue),
      capabilities: const CapabilityConfig(),
      localQaEnabled: LocalQaFlagResolver.resolve(localQaValue),
    );
  }
}
