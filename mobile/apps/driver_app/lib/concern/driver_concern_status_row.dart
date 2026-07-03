import 'package:flutter/material.dart';

class DriverConcernStatusRow extends StatelessWidget {
  const DriverConcernStatusRow({required this.marketLabel, super.key});

  final String marketLabel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        marketLabel,
        key: const Key('concern-market'),
        textAlign: TextAlign.end,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
