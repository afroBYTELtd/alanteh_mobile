import 'package:asm_app_config/asm_app_config.dart';
import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({
    required this.market,
    required this.onOpenReadiness,
    required this.onRecordConcern,
    required this.onPreviewIncomingRequest,
    super.key,
  });

  final MarketConfig market;
  final VoidCallback onOpenReadiness;
  final VoidCallback onRecordConcern;
  final VoidCallback onPreviewIncomingRequest;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final marketLabel = '${market.city}, ${market.countryName}';

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
          AsmScreenHeader(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AsmRadii.radius8),
              ),
              child: const Icon(
                Icons.electric_car_outlined,
                color: AsmColors.driverScaffold,
              ),
            ),
            title: 'ASM DRIVER',
            subtitle: 'Field workspace',
            compact: true,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            subtitleStyle: const TextStyle(color: Color(0xFFAEB8BD)),
            trailing: const AsmLocalDemoBadge(
              backgroundColor: Color(0xFF343026),
              foregroundColor: Color(0xFFFFD968),
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            ),
          ),
          const SizedBox(height: 64),
          const Icon(
            Icons.verified_user_outlined,
            color: AsmColors.solarYellow,
            size: 44,
          ),
          const SizedBox(height: AsmSpacing.space20),
          const Text(
            'Approved drivers only',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          const Text(
            'This foundation is reserved for drivers approved by '
            'Africa Solar Mobility.',
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
            iconColor: AsmColors.solarYellow,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            textMaxLines: null,
          ),
          const SizedBox(height: AsmSpacing.space16),
          const AsmEmptyStatePanel(
            compact: true,
            padding: EdgeInsets.all(18),
            backgroundColor: Color(0xFF20272B),
            borderColor: Color(0xFF3A4449),
            icon: Icons.cloud_off_outlined,
            iconColor: AsmColors.solarYellow,
            title: 'Not connected',
            message: 'No live dispatch or driver services are active.',
            titleStyle: TextStyle(fontWeight: FontWeight.w700),
            messageStyle: TextStyle(color: Color(0xFFB7C0C4)),
            textSpacing: 3,
          ),
          const SizedBox(height: AsmSpacing.space16),
          AsmPrimaryActionButton(
            key: const Key('open-readiness'),
            onPressed: onOpenReadiness,
            variant: AsmActionButtonVariant.outlined,
            icon: Icons.fact_check_outlined,
            label: 'Open readiness check',
          ),
          const SizedBox(height: AsmSpacing.space8),
          AsmPrimaryActionButton(
            key: const Key('open-concern'),
            onPressed: onRecordConcern,
            variant: AsmActionButtonVariant.text,
            icon: Icons.report_problem_outlined,
            label: 'Record local concern',
            minimumHeight: 48,
          ),
          const SizedBox(height: AsmSpacing.space4),
          AsmPrimaryActionButton(
            key: const Key('open-ride-offer-preview'),
            onPressed: onPreviewIncomingRequest,
            variant: AsmActionButtonVariant.text,
            icon: Icons.notifications_none_outlined,
            label: 'Preview incoming request',
            minimumHeight: 48,
          ),
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
