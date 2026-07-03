enum DriverReadinessItem {
  approvedShiftDetails('Shift details'),
  vehicleExterior('Vehicle outside'),
  cabinSafety('Inside the car'),
  batteryStatus('Battery');

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
