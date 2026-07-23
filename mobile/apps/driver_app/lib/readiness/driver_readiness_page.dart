import 'package:asm_app_config/asm_app_config.dart';
import 'package:flutter/material.dart';

import '../concern/driver_concern_page.dart';
import 'driver_readiness_check.dart';
import 'driver_readiness_content.dart';

class DriverReadinessPage extends StatefulWidget {
  const DriverReadinessPage({
    required this.market,
    this.initialBatteryNeedsAttention = false,
    super.key,
  });

  final MarketConfig market;
  final bool initialBatteryNeedsAttention;

  @override
  State<DriverReadinessPage> createState() => _DriverReadinessPageState();
}

class _DriverReadinessPageState extends State<DriverReadinessPage> {
  DriverReadinessCheck _check = DriverReadinessCheck.empty();
  late bool _batteryNeedsAttention;

  @override
  void initState() {
    super.initState();
    _batteryNeedsAttention = widget.initialBatteryNeedsAttention;
  }

  void _toggle(DriverReadinessItem item) {
    setState(() {
      _check = _check.toggle(item);
      if (item == DriverReadinessItem.vehicleExterior) {
        _batteryNeedsAttention = false;
      }
    });
  }

  void _reset() {
    setState(() {
      _check = _check.reset();
      _batteryNeedsAttention = false;
    });
  }

  void _markBatteryNeedsAttention() {
    setState(() {
      _batteryNeedsAttention = true;
    });
  }

  void _recheckBattery() {
    setState(() {
      _batteryNeedsAttention = false;
    });
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
      appBar: AppBar(title: const Text('Shift check · LOCAL ONLY')),
      body: DriverReadinessContent(
        market: widget.market,
        check: _check,
        batteryNeedsAttention: _batteryNeedsAttention,
        onToggle: _toggle,
        onReset: _reset,
        onReady: () => Navigator.of(context).pop(true),
        onOpenConcern: _openConcern,
        onBatteryNeedsAttention: _markBatteryNeedsAttention,
        onRecheckBattery: _recheckBattery,
      ),
    );
  }
}
