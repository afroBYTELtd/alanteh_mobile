import 'package:asm_api_client/asm_api_client.dart';
import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_auth/asm_auth.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

import 'driver_shell.dart';

export 'driver_shell.dart';

void main() {
  final configuration = AsmAppConfigLoader.fromCompileTimeEnvironment();
  runApp(DriverApp(configuration: configuration, showLoginShell: true));
}

class DriverApp extends StatelessWidget {
  const DriverApp({
    this.configuration = AsmAppConfig.localGhana,
    this.showLoginShell = false,
    this.authService,
    this.authTokenStore,
    super.key,
  });

  final AsmAppConfig configuration;
  final bool showLoginShell;
  final AuthService? authService;
  final AuthTokenStore? authTokenStore;

  @override
  Widget build(BuildContext context) {
    assert(AuthState.unauthenticated().status == AuthStatus.unauthenticated);

    final tokenStore = authTokenStore ?? SecureAuthTokenStore();
    final service =
        authService ??
        AuthService.withApiClient(
          client: AsmApiClient(baseUrl: AsmApiClient.defaultBaseUrl),
          tokenStore: tokenStore,
          appContext: AuthAppContext.driver,
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALANTEH Driver',
      theme: AsmThemes.driver,
      home: showLoginShell
          ? DriverLoginShell(
              configuration: configuration,
              authService: service,
              authTokenStore: tokenStore,
            )
          : DriverShell(configuration: configuration),
    );
  }
}

class DriverLoginShell extends StatefulWidget {
  const DriverLoginShell({
    required this.authService,
    required this.authTokenStore,
    this.configuration = AsmAppConfig.localGhana,
    super.key,
  });

  final AsmAppConfig configuration;
  final AuthService authService;
  final AuthTokenStore authTokenStore;

  @override
  State<DriverLoginShell> createState() => _DriverLoginShellState();
}

class _DriverLoginShellState extends State<DriverLoginShell> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  bool _localDemoOpened = false;
  bool _signedIn = false;
  bool _isSigningIn = false;
  String? _loginError;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _continueLocalDemo() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loginError = null;
      _localDemoOpened = true;
    });
  }

  Future<void> _signIn() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _isSigningIn) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loginError = null;
      _isSigningIn = true;
    });

    try {
      final state = await widget.authService.login(
        _phoneController.text,
        _pinController.text,
      );

      if (!mounted) {
        return;
      }

      _pinController.clear();

      if (state.isAuthenticated) {
        setState(() {
          _isSigningIn = false;
          _signedIn = true;
        });
        return;
      }

      setState(() {
        _isSigningIn = false;
        _loginError = _driverLoginErrorMessage(state.error);
      });
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginError = _driverLoginErrorMessage(error);
      });
    } on Object {
      if (!mounted) {
        return;
      }
      _pinController.clear();
      setState(() {
        _isSigningIn = false;
        _loginError = 'Could not sign in. Please check your phone and PIN.';
      });
    }
  }

  void _clearForm() {
    FocusManager.instance.primaryFocus?.unfocus();
    _phoneController.clear();
    _pinController.clear();
    _formKey.currentState?.reset();
    setState(() => _loginError = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_localDemoOpened || _signedIn) {
      return DriverShell(configuration: widget.configuration);
    }

    return Scaffold(
      body: AsmScreenSurface(
        scrollable: true,
        expandToViewport: true,
        padding: const EdgeInsets.fromLTRB(
          22,
          AsmSpacing.space20,
          22,
          AsmSpacing.space24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AsmScreenHeader(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(AsmRadii.radius8),
                  ),
                  child: const Icon(
                    Icons.electric_car_outlined,
                    color: AsmColors.driverScaffold,
                  ),
                ),
                title: 'ALANTEH',
                subtitle: 'Driver',
                compact: true,
              ),
              const SizedBox(height: 64),
              const Icon(
                Icons.verified_user_outlined,
                color: AsmColors.solarYellow,
                size: 44,
              ),
              const SizedBox(height: AsmSpacing.space20),
              const Text(
                'Driver access',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              const Text(
                'Enter your phone number and PIN to continue.',
                style: TextStyle(
                  color: AsmColors.driverTextSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AsmSpacing.space20),
              TextFormField(
                key: const Key('driver-phone-field'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Phone number cannot be blank.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AsmSpacing.space12),
              TextFormField(
                key: const Key('driver-pin-field'),
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _signIn(),
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'PIN cannot be blank.';
                  }
                  return null;
                },
              ),
              if (_loginError != null) ...[
                const SizedBox(height: AsmSpacing.space16),
                _DriverLoginErrorPanel(message: _loginError!),
              ],
              const SizedBox(height: AsmSpacing.space20),
              AsmPrimaryActionButton(
                key: const Key('driver-sign-in'),
                onPressed: _isSigningIn ? null : _signIn,
                icon: Icons.login_outlined,
                label: _isSigningIn ? 'Signing in...' : 'Sign in',
              ),
              const SizedBox(height: AsmSpacing.space8),
              AsmPrimaryActionButton(
                key: const Key('driver-continue-local-demo'),
                onPressed: _isSigningIn ? null : _continueLocalDemo,
                variant: AsmActionButtonVariant.text,
                icon: Icons.play_arrow_outlined,
                label: 'Continue without signing in',
                minimumHeight: 48,
              ),
              const SizedBox(height: AsmSpacing.space8),
              AsmPrimaryActionButton(
                key: const Key('driver-clear-form'),
                onPressed: _isSigningIn ? null : _clearForm,
                variant: AsmActionButtonVariant.text,
                icon: Icons.clear_outlined,
                label: 'Clear form',
                minimumHeight: 48,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _driverLoginErrorMessage(AuthException? error) {
    if (error?.message == authAppContextErrorMessage) {
      return authAppContextErrorMessage;
    }

    if (error?.type == AuthExceptionType.validation) {
      return error!.message;
    }

    return 'Could not sign in. Please check your phone and PIN.';
  }
}

class _DriverLoginErrorPanel extends StatelessWidget {
  const _DriverLoginErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('driver-login-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space12),
      decoration: BoxDecoration(
        color: AsmColors.driverScaffold,
        borderRadius: BorderRadius.circular(AsmRadii.radius8),
        border: Border.all(color: AsmColors.driverWarningSurface),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AsmColors.driverWarningSurface,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}
