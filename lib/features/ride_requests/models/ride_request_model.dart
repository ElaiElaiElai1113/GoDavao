class RideRequest {
  final String passengerId;
  final double pickupLat;
  final double pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final String? driverRouteId;

  RideRequest({
    required this.passengerId,
    required this.pickupLat,
    required this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.driverRouteId,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'passenger_id': passengerId,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
    };
    if (destinationLat != null && destinationLng != null) {
      map['destination_lat'] = destinationLat;
      map['destination_lng'] = destinationLng;
    }
    if (driverRouteId != null) {
      map['driver_route_id'] = driverRouteId;
    }
    return map;
  }
}
