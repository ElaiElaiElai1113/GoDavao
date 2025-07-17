class DriverRoute {
  final String driverId;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;

  DriverRoute({
    required this.driverId,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });

  Map<String, dynamic> toMap() => {
    'driver_id': driverId,
    'start_lat': startLat,
    'start_lng': startLng,
    'end_lat': endLat,
    'end_lng': endLng,
  };
}
