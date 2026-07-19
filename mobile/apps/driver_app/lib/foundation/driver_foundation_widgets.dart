import 'dart:async';

import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

class DriverSplashGate extends StatefulWidget {
  const DriverSplashGate({
    required this.child,
    this.duration = const Duration(milliseconds: 900),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  State<DriverSplashGate> createState() => _DriverSplashGateState();
}

class _DriverSplashGateState extends State<DriverSplashGate> {
  Timer? _timer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: _showSplash
          ? const DriverSplashScreen()
          : KeyedSubtree(
              key: const Key('driver-splash-complete'),
              child: widget.child,
            ),
    );
  }
}

class DriverSplashScreen extends StatelessWidget {
  const DriverSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('driver-splash-screen'),
      backgroundColor: AsmColors.driverVisualSurface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AsmSpacing.space32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 118,
                  height: 118,
                  padding: const EdgeInsets.all(AsmSpacing.space20),
                  decoration: BoxDecoration(
                    color: AsmColors.driverCard,
                    borderRadius: BorderRadius.circular(AsmRadii.radius28),
                    border: Border.all(color: AsmColors.driverLine),
                  ),
                  child: Image.asset(
                    'assets/brand/alanteh_header_white.png',
                    key: const Key('driver-splash-logo'),
                    fit: BoxFit.contain,
                    semanticLabel: 'ALANTEH Driver',
                  ),
                ),
                const SizedBox(height: AsmSpacing.space24),
                const Text(
                  'ALANTEH Driver',
                  style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: AsmSpacing.space8),
                const Text(
                  'Safe, reliable electric mobility',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AsmColors.driverTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DriverWaitingForOfferPanel extends StatelessWidget {
  const DriverWaitingForOfferPanel({this.onPreviewIncomingOffer, super.key});

  final VoidCallback? onPreviewIncomingOffer;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('driver-waiting-for-offer'),
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.driverCardElevated,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(color: AsmColors.driverLine),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 34,
            backgroundColor: AsmColors.driverCard,
            foregroundColor: AsmColors.driverMintAction,
            child: Icon(Icons.notifications_active_outlined, size: 34),
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Waiting for offers',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'WAITING FOR A RIDE OFFER NEARBY',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AsmColors.driverMintAction,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const Text(
            'Stay in your zone for faster matches.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AsmColors.driverTextSecondary, height: 1.4),
          ),
          if (onPreviewIncomingOffer != null) ...[
            const SizedBox(height: AsmSpacing.space20),
            AsmPrimaryActionButton(
              key: const Key('open-ride-offer-preview'),
              onPressed: onPreviewIncomingOffer,
              icon: Icons.notifications_none_outlined,
              label: 'Preview incoming offer',
            ),
          ],
        ],
      ),
    );
  }
}

class DriverOfflineState extends StatelessWidget {
  const DriverOfflineState({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('driver-offline-screen'),
      backgroundColor: AsmColors.driverVisualSurface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AsmSpacing.space24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AsmSpacing.space24),
              decoration: BoxDecoration(
                color: AsmColors.driverCard,
                borderRadius: BorderRadius.circular(AsmRadii.radius28),
                border: Border.all(color: AsmColors.driverLine),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    key: Key('driver-offline-icon'),
                    size: 64,
                    color: AsmColors.driverWarningSurface,
                  ),
                  const SizedBox(height: AsmSpacing.space16),
                  const Text(
                    'You’re offline',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                  const Text(
                    "Check your connection. You can't receive ride offers "
                    'or update your shift status while offline.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AsmColors.driverTextSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AsmSpacing.space24),
                  AsmPrimaryActionButton(
                    key: const Key('driver-offline-retry'),
                    onPressed: onRetry,
                    icon: Icons.refresh,
                    label: 'Retry',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
