class RideRequest {
  final String passengerId;
  final double pickupLat;
  final double pickupLng;
  final double destinationLat;
  final double destinationLng;

  RideRequest({
    required this.passengerId,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationLat,
    required this.destinationLng,
  });

  Map<String, dynamic> toMap() {
    return {
      'passenger_id': passengerId,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'status': 'pending',
    };
  }
}
