import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

class DriverConcernStatusRow extends StatelessWidget {
  const DriverConcernStatusRow({required this.marketLabel, super.key});

  final String marketLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AsmSpacing.space12,
            vertical: AsmSpacing.space8,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AsmRadii.radius6),
          ),
          child: Text(
            'LOCAL DEMO',
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            marketLabel,
            key: const Key('concern-market'),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
