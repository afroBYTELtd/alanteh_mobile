enum DriverReadinessItem {
  approvedShiftDetails('Vehicle check'),
  vehicleExterior('Battery check'),
  cabinSafety('Phone & app check'),
  batteryStatus('Safety check');

  const DriverReadinessItem(this.label);

  final String label;

  String get description {
    return switch (this) {
      DriverReadinessItem.approvedShiftDetails =>
        'Tyres, lights, and body condition',
      DriverReadinessItem.vehicleExterior =>
        'Charge level and secure connections',
      DriverReadinessItem.cabinSafety =>
        'App updated and location access enabled',
      DriverReadinessItem.batteryStatus =>
        'Seatbelt, first aid kit, and driver badge',
    };
  }
}

final class DriverReadinessCheck {
  factory DriverReadinessCheck.empty() {
    return DriverReadinessCheck._(completedItems: const {});
  }

  DriverReadinessCheck._({required Set<DriverReadinessItem> completedItems})
    : completedItems = Set.unmodifiable(completedItems);

  final Set<DriverReadinessItem> completedItems;

  int get completedCount => completedItems.length;

  bool get isComplete => completedCount == DriverReadinessItem.values.length;

  DriverReadinessCheck toggle(DriverReadinessItem item) {
    final updatedItems = Set<DriverReadinessItem>.of(completedItems);
    if (!updatedItems.add(item)) {
      updatedItems.remove(item);
    }
    return DriverReadinessCheck._(completedItems: updatedItems);
  }

  DriverReadinessCheck reset() => DriverReadinessCheck.empty();
}
