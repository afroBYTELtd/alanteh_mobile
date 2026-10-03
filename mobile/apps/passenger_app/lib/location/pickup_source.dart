/// How the pickup pin got where the passenger confirmed it.
enum PassengerPickupSource {
  /// Recenter moved it to the device's location.
  gps('gps'),

  /// A place search result moved it.
  search('search'),

  /// The passenger moved the map.
  dragged('dragged');

  const PassengerPickupSource(this.wireValue);

  /// The `pickup_source` value the booking endpoint accepts.
  final String wireValue;
}
