import 'package:asm_app_config/asm_app_config.dart';
import 'package:flutter/material.dart';

import '../concern/driver_concern_page.dart';
import '../network/driver_report_gateway.dart';
import 'driver_readiness_check.dart';
import 'driver_readiness_content.dart';
import 'driver_shift_check_submission.dart';

class DriverReadinessPage extends StatefulWidget {
  const DriverReadinessPage({
    required this.market,
    this.initialBatteryNeedsAttention = false,
    this.submissionController,
    this.driverReportGateway,
    this.deviceNow,
    this.navigationDelay = const Duration(seconds: 2),
    super.key,
  });

  final MarketConfig market;
  final bool initialBatteryNeedsAttention;
  final DriverShiftCheckSubmissionController? submissionController;
  final DriverReportGateway? driverReportGateway;
  final DateTime Function()? deviceNow;
  final Duration navigationDelay;

  @override
  State<DriverReadinessPage> createState() => _DriverReadinessPageState();
}

class _DriverReadinessPageState extends State<DriverReadinessPage> {
  DriverReadinessCheck _check = DriverReadinessCheck.empty();
  late bool _batteryNeedsAttention;
  late bool _batteryAttentionWasShown;
  DriverReadinessSubmissionState _submissionState =
      DriverReadinessSubmissionState.idle;

  @override
  void initState() {
    super.initState();
    _batteryNeedsAttention = widget.initialBatteryNeedsAttention;
    _batteryAttentionWasShown = widget.initialBatteryNeedsAttention;
  }

  void _toggle(DriverReadinessItem item) {
    if (_submissionState != DriverReadinessSubmissionState.idle) {
      return;
    }

    setState(() {
      _check = _check.toggle(item);
      if (item == DriverReadinessItem.vehicleExterior) {
        _batteryNeedsAttention = false;
      }
    });
  }

  void _reset() {
    if (_submissionState != DriverReadinessSubmissionState.idle) {
      return;
    }

    setState(() {
      _check = _check.reset();
      _batteryNeedsAttention = false;
      _batteryAttentionWasShown = false;
    });
  }

  void _markBatteryNeedsAttention() {
    if (_submissionState != DriverReadinessSubmissionState.idle) {
      return;
    }

    setState(() {
      _batteryNeedsAttention = true;
      _batteryAttentionWasShown = true;
    });
  }

  void _recheckBattery() {
    if (_submissionState != DriverReadinessSubmissionState.idle) {
      return;
    }

    setState(() {
      _batteryNeedsAttention = false;
    });
  }

  Future<void> _submitShiftCheck() async {
    if (_submissionState != DriverReadinessSubmissionState.idle ||
        !_check.isComplete ||
        _batteryNeedsAttention) {
      return;
    }

    setState(() {
      _submissionState = DriverReadinessSubmissionState.submitting;
    });

    final submittedAt = widget.deviceNow?.call() ?? DateTime.now();
    final submission = DriverShiftCheckSubmission.fromReadiness(
      check: _check,
      batteryNeedsAttention: _batteryAttentionWasShown,
      submittedAt: submittedAt,
    );

    final controller = widget.submissionController;
    DriverShiftCheckSubmissionDisposition disposition;

    if (controller == null) {
      disposition = DriverShiftCheckSubmissionDisposition.queued;
    } else {
      try {
        final result = await controller.submit(submission);
        disposition = result.disposition;
      } on Object {
        disposition = DriverShiftCheckSubmissionDisposition.queued;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _submissionState =
          disposition == DriverShiftCheckSubmissionDisposition.submitted
          ? DriverReadinessSubmissionState.submitted
          : DriverReadinessSubmissionState.queued;
    });

    await Future<void>.delayed(widget.navigationDelay);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(disposition);
  }

  Future<void> _openConcern() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverConcernPage(
          market: widget.market,
          gateway: widget.driverReportGateway,
        ),
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
        submissionState: _submissionState,
        batteryNeedsAttention: _batteryNeedsAttention,
        onToggle: _toggle,
        onReset: _reset,
        onReady: _submitShiftCheck,
        onOpenConcern: _openConcern,
        onBatteryNeedsAttention: _markBatteryNeedsAttention,
        onRecheckBattery: _recheckBattery,
      ),
    );
  }
}
