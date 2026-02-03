import 'package:latlong2/latlong.dart';

/// Model representing a ride match between a driver and passenger.
class MatchCard {
  final String matchId;
  final String rideRequestId;
  final String? driverRouteId;
  final String status;
  final DateTime createdAt;
  final String? driverRouteName;
  final String passengerName;
  final String? passengerId;
  final String pickupAddress;
  final String destinationAddress;
  final double? fare;
  final int pax;

  // Map coordinates
  final double? pickupLat;
  final double? pickupLng;
  final double? destLat;
  final double? destLng;

  // Ratings
  final double? ratingAvg;
  final int? ratingCount;

  const MatchCard({
    required this.matchId,
    required this.rideRequestId,
    required this.status,
    required this.createdAt,
    required this.passengerName,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pax,
    this.driverRouteId,
    this.driverRouteName,
    this.passengerId,
    this.fare,
    this.pickupLat,
    this.pickupLng,
    this.destLat,
    this.destLng,
    this.ratingAvg,
    this.ratingCount,
  });

  /// Whether this match has valid coordinate data
  bool get hasCoords =>
      pickupLat != null &&
      pickupLng != null &&
      destLat != null &&
      destLng != null;

  /// Get pickup coordinate as LatLng
  LatLng? get pickup =>
      hasCoords ? LatLng(pickupLat!, pickupLng!) : null;

  /// Get destination coordinate as LatLng
  LatLng? get destination =>
      hasCoords ? LatLng(destLat!, destLng!) : null;

  /// Whether this match is in pending state
  bool get isPending => status == 'pending';

  /// Whether this match is accepted
  bool get isAccepted => status == 'accepted';

  /// Whether this match is active (en_route)
  bool get isActive => status == 'en_route';

  /// Whether this match is completed
  bool get isCompleted => status == 'completed';

  /// Whether this match is declined or cancelled
  bool get isFailed =>
      status == 'declined' ||
      status == 'cancelled' ||
      status == 'canceled';

  /// Create a copy with updated fields
  MatchCard copyWith({
    String? matchId,
    String? rideRequestId,
    String? driverRouteId,
    String? status,
    DateTime? createdAt,
    String? driverRouteName,
    String? passengerName,
    String? passengerId,
    String? pickupAddress,
    String? destinationAddress,
    double? fare,
    int? pax,
    double? pickupLat,
    double? pickupLng,
    double? destLat,
    double? destLng,
    double? ratingAvg,
    int? ratingCount,
  }) {
    return MatchCard(
      matchId: matchId ?? this.matchId,
      rideRequestId: rideRequestId ?? this.rideRequestId,
      driverRouteId: driverRouteId ?? this.driverRouteId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      passengerName: passengerName ?? this.passengerName,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      pax: pax ?? this.pax,
      driverRouteName: driverRouteName ?? this.driverRouteName,
      passengerId: passengerId ?? this.passengerId,
      fare: fare ?? this.fare,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      destLat: destLat ?? this.destLat,
      destLng: destLng ?? this.destLng,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
    );
  }

  /// Create MatchCard from a Supabase row
  factory MatchCard.fromRow(Map<String, dynamic> row) {
    return MatchCard(
      matchId: row['id'] as String,
      rideRequestId: row['ride_request_id'] as String? ?? '',
      driverRouteId: row['driver_route_id'] as String?,
      status: row['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(row['created_at'] as String? ?? DateTime.now().toIso8601String()),
      passengerName: row['passenger_name'] as String? ?? 'Passenger',
      pickupAddress: row['pickup_address'] as String? ?? '',
      destinationAddress: row['dropoff_address'] as String? ?? '',
      fare: (row['fare'] as num?)?.toDouble(),
      pax: row['seats_allocated'] as int? ?? 1,
      driverRouteName: row['route_name'] as String?,
      passengerId: row['passenger_id'] as String?,
      pickupLat: (row['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (row['pickup_lng'] as num?)?.toDouble(),
      destLat: (row['dropoff_lat'] as num?)?.toDouble(),
      destLng: (row['dropoff_lng'] as num?)?.toDouble(),
      ratingAvg: (row['rating_avg'] as num?)?.toDouble(),
      ratingCount: row['rating_count'] as int?,
    );
  }

  @override
  String toString() =>
      'MatchCard(matchId: $matchId, passenger: $passengerName, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchCard &&
          runtimeType == other.runtimeType &&
          matchId == other.matchId;

  @override
  int get hashCode => matchId.hashCode;
}
