import 'package:asm_design_system/asm_design_system.dart';
import 'package:flutter/material.dart';

enum DriverShiftStatus { notStarted, inProgress, completed }

@immutable
final class DriverShiftRecord {
  const DriverShiftRecord({
    required this.id,
    required this.dateLabel,
    required this.dutyLabel,
    required this.status,
    required this.onlineDurationLabel,
    required this.completedTrips,
    required this.vehicleLabel,
    required this.serviceAreaLabel,
  });

  final String id;
  final String dateLabel;
  final String dutyLabel;
  final DriverShiftStatus status;
  final String onlineDurationLabel;
  final int completedTrips;
  final String vehicleLabel;
  final String serviceAreaLabel;

  String get statusLabel => switch (status) {
    DriverShiftStatus.notStarted => 'Not started',
    DriverShiftStatus.inProgress => 'In progress',
    DriverShiftStatus.completed => 'Completed',
  };

  String get tripCountLabel => switch (status) {
    DriverShiftStatus.inProgress => '$completedTrips so far',
    DriverShiftStatus.notStarted => '$completedTrips',
    DriverShiftStatus.completed => '$completedTrips completed',
  };
}

class DriverShiftSummaryPage extends StatelessWidget {
  const DriverShiftSummaryPage({
    required this.currentShift,
    this.completedShifts = const <DriverShiftRecord>[],
    super.key,
  });

  final DriverShiftRecord currentShift;
  final List<DriverShiftRecord> completedShifts;

  void _openHistory(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverShiftHistoryPage(
          currentShift: currentShift,
          completedShifts: completedShifts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsmColors.driverScaffold,
      appBar: AppBar(title: const Text('Shift summary')),
      body: AsmScreenSurface(
        key: const Key('driver-shift-summary-screen'),
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
            const Text(
              'Current shift',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: AsmSpacing.space8),
            Text(
              currentShift.dateLabel,
              style: const TextStyle(
                color: AsmColors.driverTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AsmSpacing.space20),
            _ShiftSectionCard(
              key: const Key('driver-current-shift-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          currentShift.dutyLabel,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _ShiftStatusPill(record: currentShift),
                    ],
                  ),
                  const SizedBox(height: AsmSpacing.space20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ShiftMetric(
                          label: 'Online time',
                          value: currentShift.onlineDurationLabel,
                        ),
                      ),
                      const SizedBox(width: AsmSpacing.space12),
                      Expanded(
                        child: _ShiftMetric(
                          label: 'Trips',
                          value: currentShift.tripCountLabel,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AsmSpacing.space16),
            _ShiftSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Shift details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: AsmSpacing.space16),
                  _ShiftDetailRow(
                    label: 'Vehicle',
                    value: currentShift.vehicleLabel,
                  ),
                  _ShiftDetailRow(
                    label: 'Service area',
                    value: currentShift.serviceAreaLabel,
                  ),
                  _ShiftDetailRow(
                    label: 'Completed trips',
                    value: '${currentShift.completedTrips}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AsmSpacing.space20),
            AsmPrimaryActionButton(
              key: const Key('open-shift-history'),
              onPressed: () => _openHistory(context),
              variant: AsmActionButtonVariant.outlined,
              icon: Icons.history_outlined,
              label: 'View shift history',
            ),
          ],
        ),
      ),
    );
  }
}

class DriverShiftHistoryPage extends StatelessWidget {
  const DriverShiftHistoryPage({
    this.currentShift,
    this.completedShifts = const <DriverShiftRecord>[],
    super.key,
  });

  final DriverShiftRecord? currentShift;
  final List<DriverShiftRecord> completedShifts;

  void _openDetail(BuildContext context, DriverShiftRecord record) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverShiftDetailPage(record: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyRecord = currentShift != null || completedShifts.isNotEmpty;

    return Scaffold(
      backgroundColor: AsmColors.driverScaffold,
      appBar: AppBar(title: const Text('Shift history')),
      body: AsmScreenSurface(
        key: const Key('driver-shift-history-screen'),
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
            if (!hasAnyRecord)
              const AsmEmptyStatePanel(
                key: Key('driver-shift-history-empty'),
                compact: false,
                icon: Icons.history_outlined,
                iconColor: AsmColors.driverMintAction,
                title: 'No shift history yet',
                message:
                    'Completed shifts will appear here after they are recorded.',
              )
            else ...[
              if (currentShift case final shift?) ...[
                const Text(
                  'Current shift',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AsmSpacing.space12),
                _ShiftRecordCard(
                  record: shift,
                  onTap: () => _openDetail(context, shift),
                ),
                const SizedBox(height: AsmSpacing.space24),
              ],
              const Text(
                'Past shifts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AsmSpacing.space12),
              if (completedShifts.isEmpty)
                const AsmEmptyStatePanel(
                  key: Key('driver-shift-history-completed-empty'),
                  compact: true,
                  icon: Icons.event_available_outlined,
                  iconColor: AsmColors.driverMintAction,
                  title: 'No completed shifts yet',
                  message: 'Completed shift records will appear here.',
                )
              else
                for (final record in completedShifts) ...[
                  _ShiftRecordCard(
                    record: record,
                    onTap: () => _openDetail(context, record),
                  ),
                  const SizedBox(height: AsmSpacing.space12),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

class DriverShiftDetailPage extends StatelessWidget {
  const DriverShiftDetailPage({required this.record, super.key});

  final DriverShiftRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AsmColors.driverScaffold,
      appBar: AppBar(title: const Text('Shift detail')),
      body: AsmScreenSurface(
        key: const Key('driver-shift-detail-screen'),
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
            Text(
              record.dateLabel,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: AsmSpacing.space12),
            _ShiftStatusPill(record: record),
            const SizedBox(height: AsmSpacing.space20),
            _ShiftSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShiftDetailRow(
                    label: 'Duty status',
                    value: record.dutyLabel,
                  ),
                  _ShiftDetailRow(
                    label: 'Shift status',
                    value: record.statusLabel,
                  ),
                  _ShiftDetailRow(
                    label: 'Online time',
                    value: record.onlineDurationLabel,
                  ),
                  _ShiftDetailRow(
                    label: 'Completed trips',
                    value: '${record.completedTrips}',
                  ),
                  _ShiftDetailRow(label: 'Vehicle', value: record.vehicleLabel),
                  _ShiftDetailRow(
                    label: 'Service area',
                    value: record.serviceAreaLabel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftRecordCard extends StatelessWidget {
  const _ShiftRecordCard({required this.record, required this.onTap});

  final DriverShiftRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey<String>('driver-shift-record-${record.id}'),
      color: AsmColors.driverCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        side: const BorderSide(color: AsmColors.driverLine),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        child: Padding(
          padding: const EdgeInsets.all(AsmSpacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record.dateLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AsmColors.driverTextSecondary,
                  ),
                ],
              ),
              const SizedBox(height: AsmSpacing.space12),
              Row(
                children: [
                  Expanded(
                    child: _ShiftMetric(
                      label: record.dutyLabel,
                      value: record.onlineDurationLabel,
                    ),
                  ),
                  const SizedBox(width: AsmSpacing.space12),
                  Expanded(
                    child: _ShiftMetric(
                      label: 'Trips',
                      value: record.tripCountLabel,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftStatusPill extends StatelessWidget {
  const _ShiftStatusPill({required this.record});

  final DriverShiftRecord record;

  @override
  Widget build(BuildContext context) {
    final isActive = record.status == DriverShiftStatus.inProgress;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AsmSpacing.space12,
        vertical: AsmSpacing.space8,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? AsmColors.driverCardElevated
            : AsmColors.driverScaffold,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(
          color: isActive ? AsmColors.driverMintAction : AsmColors.driverLine,
        ),
      ),
      child: Text(
        record.statusLabel,
        style: TextStyle(
          color: isActive
              ? AsmColors.driverMintAction
              : AsmColors.driverTextSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ShiftMetric extends StatelessWidget {
  const _ShiftMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AsmColors.driverTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AsmSpacing.space4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ShiftDetailRow extends StatelessWidget {
  const _ShiftDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AsmSpacing.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                color: AsmColors.driverTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AsmSpacing.space8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w900, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftSectionCard extends StatelessWidget {
  const _ShiftSectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(AsmSpacing.space20),
      decoration: BoxDecoration(
        color: AsmColors.driverCard,
        borderRadius: BorderRadius.circular(AsmRadii.radius24),
        border: Border.all(color: AsmColors.driverLine),
      ),
      child: child,
    );
  }
}
