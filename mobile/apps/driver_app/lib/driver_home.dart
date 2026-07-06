import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({
    required this.market,
    required this.isOnShift,
    required this.onOpenReadiness,
    required this.onRecordConcern,
    required this.onPreviewIncomingRequest,
    required this.localQaEnabled,
    this.onSignOut,
    super.key,
  });

  final MarketConfig market;
  final bool isOnShift;
  final VoidCallback onOpenReadiness;
  final VoidCallback onRecordConcern;
  final VoidCallback onPreviewIncomingRequest;
  final bool localQaEnabled;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final marketLabel = market.countryName;
    final shiftLabel = localQaEnabled
        ? (isOnShift ? 'Local QA: On shift' : 'Local QA: Off shift')
        : 'Control Center will confirm your duty status.';

    return AsmScreenSurface(
      scrollable: true,
      expandToViewport: true,
      padding: const EdgeInsets.fromLTRB(
        22,
        AsmSpacing.space20,
        22,
        AsmSpacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DriverHomeBrandHeader(shiftLabel: shiftLabel, onSignOut: onSignOut),
          const SizedBox(height: 64),
          const Icon(
            Icons.verified_user_outlined,
            color: AsmColors.brandGreen,
            size: 44,
          ),
          const SizedBox(height: AsmSpacing.space20),
          const Text(
            'Approved drivers only',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          const Text(
            'This workspace is reserved for approved ALANTEH drivers.',
            style: TextStyle(
              color: Color(0xFFB7C0C4),
              fontSize: 17,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AsmSpacing.space20),
          AsmSectionLabel(
            key: const Key('driver-market'),
            text: marketLabel,
            icon: Icons.location_on_outlined,
            iconColor: AsmColors.brandGreen,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            textMaxLines: null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          const Text(
            'Today',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AsmSpacing.space8),
          const AsmEmptyStatePanel(
            key: Key('driver-live-safe-waiting'),
            compact: true,
            padding: EdgeInsets.all(18),
            backgroundColor: Color(0xFF20272B),
            borderColor: Color(0xFF3A4449),
            icon: Icons.route_outlined,
            iconColor: AsmColors.brandGreen,
            title: 'No trip assigned yet.',
            message: 'Stay ready for the Control Center.',
            titleStyle: TextStyle(fontWeight: FontWeight.w700),
            messageStyle: TextStyle(color: Color(0xFFB7C0C4)),
            textSpacing: 3,
          ),
          const SizedBox(height: AsmSpacing.space16),
          if (localQaEnabled) ...[
            AsmPrimaryActionButton(
              key: const Key('open-readiness'),
              onPressed: onOpenReadiness,
              variant: AsmActionButtonVariant.outlined,
              icon: Icons.fact_check_outlined,
              label: 'Local QA readiness preview',
            ),
            const SizedBox(height: AsmSpacing.space8),
          ],
          AsmPrimaryActionButton(
            key: const Key('open-concern'),
            onPressed: onRecordConcern,
            variant: AsmActionButtonVariant.text,
            icon: Icons.report_problem_outlined,
            label: 'Report an issue',
            minimumHeight: 48,
          ),
          if (localQaEnabled) ...[
            const SizedBox(height: AsmSpacing.space4),
            AsmPrimaryActionButton(
              key: const Key('open-ride-offer-preview'),
              onPressed: onPreviewIncomingRequest,
              variant: AsmActionButtonVariant.text,
              icon: Icons.notifications_none_outlined,
              label: 'Local QA trip preview',
              minimumHeight: 48,
            ),
          ],
          const SizedBox(height: AsmSpacing.space16),
          const AsmSectionLabel(
            text: 'Driver app foundation',
            textStyle: TextStyle(color: Color(0xFF8F9A9F), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _DriverHomeBrandHeader extends StatelessWidget {
  const _DriverHomeBrandHeader({
    required this.shiftLabel,
    required this.onSignOut,
  });

  final String shiftLabel;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/brand/alanteh_header_white.png',
                key: const Key('driver-home-brand-logo'),
                height: 34,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                semanticLabel: 'ALANTEH driver logo',
              ),
              const SizedBox(height: 6),
              const Text(
                'Field workspace',
                style: TextStyle(color: Color(0xFFAEB8BD)),
              ),
              const SizedBox(height: 8),
              Container(
                key: const Key('driver-duty-status'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AsmColors.driverPanelMuted,
                  borderRadius: BorderRadius.circular(AsmRadii.radius6),
                ),
                child: Text(
                  shiftLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (onSignOut != null) ...[
          const SizedBox(width: AsmSpacing.space12),
          TextButton.icon(
            key: const Key('driver-sign-out'),
            onPressed: onSignOut,
            icon: const Icon(Icons.exit_to_app_outlined, size: 16),
            label: const Text('Sign out'),
          ),
        ],
      ],
    );
  }
}
