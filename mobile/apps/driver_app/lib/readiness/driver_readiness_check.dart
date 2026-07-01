enum DriverReadinessItem {
  approvedShiftDetails('Approved shift details confirmed'),
  vehicleExterior('Tyres, lights and vehicle exterior checked'),
  cabinSafety('Seat belts and cabin safety checked'),
  batteryStatus('Battery status and visible warnings checked');

  const DriverReadinessItem(this.label);

  final String label;
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
