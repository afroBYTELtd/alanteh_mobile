import 'package:asm_app_config/asm_app_config.dart';
import 'package:flutter/material.dart';

import '../concern/driver_concern_page.dart';
import 'driver_readiness_check.dart';
import 'driver_readiness_content.dart';

class DriverReadinessPage extends StatefulWidget {
  const DriverReadinessPage({required this.market, super.key});

  final MarketConfig market;

  @override
  State<DriverReadinessPage> createState() => _DriverReadinessPageState();
}

class _DriverReadinessPageState extends State<DriverReadinessPage> {
  DriverReadinessCheck _check = DriverReadinessCheck.empty();

  void _toggle(DriverReadinessItem item) {
    setState(() => _check = _check.toggle(item));
  }

  void _reset() {
    setState(() => _check = _check.reset());
  }

  Future<void> _openConcern() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverConcernPage(market: widget.market),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shift check')),
      body: DriverReadinessContent(
        market: widget.market,
        check: _check,
        onToggle: _toggle,
        onReset: _reset,
        onOpenConcern: _openConcern,
      ),
    );
  }
}
