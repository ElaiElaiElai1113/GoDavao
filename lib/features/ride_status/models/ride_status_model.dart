import 'package:latlong2/latlong.dart';
import 'package:godavao/core/fare_service.dart';

/// Model representing the current status of a ride for a passenger.
class RideStatus {
  // Core ride data
  final Map<String, dynamic>? ride;
  final Map<String, dynamic>? payment;
  final String? passengerNote;

  // Pricing data saved at ride confirmation time
  final double? fareBasis;
  final double? carpoolDiscountPctActual;
  final String? weatherDesc;

  // Live tracking data
  final LatLng? driverLive;
  final LatLng? myLive;
  final DateTime? driverLastAt;
  final DateTime? selfLastAt;

  // Computed fare breakdown
  final FareBreakdown? fareBreakdown;

  // Platform configuration
  final double platformFeeRate;

  const RideStatus({
    this.ride,
    this.payment,
    this.passengerNote,
    this.fareBasis,
    this.carpoolDiscountPctActual,
    this.weatherDesc,
    this.driverLive,
    this.myLive,
    this.driverLastAt,
    this.selfLastAt,
    this.fareBreakdown,
    this.platformFeeRate = 0.15,
  });

  /// Get the current status string
  String get status {
    if (ride == null) return 'unknown';
    return ride!['status'] as String? ?? 'unknown';
  }

  /// Get the status as an enum for easier handling
  RideStatusType get statusType {
    switch (status) {
      case 'pending':
        return RideStatusType.pending;
      case 'matched':
        return RideStatusType.matched;
      case 'accepted':
        return RideStatusType.accepted;
      case 'en_route':
        return RideStatusType.enRoute;
      case 'picked_up':
        return RideStatusType.pickedUp;
      case 'dropped_off':
        return RideStatusType.droppedOff;
      case 'completed':
        return RideStatusType.completed;
      case 'cancelled':
      case 'canceled':
        return RideStatusType.cancelled;
      case 'declined':
        return RideStatusType.declined;
      default:
        return RideStatusType.unknown;
    }
  }

  /// Get the display color for the current status
  /// Caller should pass BuildContext to get theme colors
  String getStatusColorHex() {
    switch (statusType) {
      case RideStatusType.pending:
        return '#FF9C27B0'; // Orange
      case RideStatusType.matched:
        return '#FF2196F3'; // Blue
      case RideStatusType.accepted:
        return '#FF4CAF50'; // Green
      case RideStatusType.enRoute:
        return '#FF9C27B0'; // Purple
      case RideStatusType.pickedUp:
        return '#FF00BCD4'; // Cyan
      case RideStatusType.droppedOff:
        return '#FF3F51B5'; // Indigo
      case RideStatusType.completed:
        return '#FF4CAF50'; // Green
      case RideStatusType.cancelled:
      case RideStatusType.declined:
        return '#FFF44336'; // Red
      default:
        return '#FF9E9E9E'; // Grey
    }
  }

  /// Get pickup coordinates
  LatLng? get pickup {
    if (ride == null) return null;
    final lat = ride!['pickup_lat'] as num?;
    final lng = ride!['pickup_lng'] as num?;
    if (lat != null && lng != null) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  /// Get dropoff coordinates
  LatLng? get dropoff {
    if (ride == null) return null;
    final lat = ride!['dropoff_lat'] as num?;
    final lng = ride!['dropoff_lng'] as num?;
    if (lat != null && lng != null) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  /// Get the passenger ID
  String? get passengerId {
    if (ride == null) return null;
    return ride!['passenger_id'] as String?;
  }

  /// Get the driver ID
  String? get driverId {
    if (ride == null) return null;
    return ride!['driver_id'] as String?;
  }

  /// Get the match ID
  String? get matchId {
    if (ride == null) return null;
    return ride!['match_id'] as String?;
  }

  /// Get the number of seats requested
  int get seatsRequested {
    if (ride == null) return 1;
    return ride!['seats_requested'] as int? ?? 1;
  }

  /// Check if the ride is currently active
  bool get isActive {
    final type = statusType;
    return type == RideStatusType.accepted ||
        type == RideStatusType.enRoute ||
        type == RideStatusType.pickedUp;
  }

  /// Check if the ride is completed
  bool get isCompleted => statusType == RideStatusType.completed;

  /// Check if the ride has failed
  bool get isFailed {
    final type = statusType;
    return type == RideStatusType.cancelled ||
        type == RideStatusType.declined;
  }

  /// Check if chat should be disabled
  bool get isChatLocked => isCompleted || isFailed;

  /// Get payment status
  String get paymentStatus {
    if (payment == null) return 'unknown';
    return payment!['status'] as String? ?? 'pending';
  }

  /// Check if payment is completed
  bool get isPaymentComplete => paymentStatus == 'completed' || paymentStatus == 'paid';

  /// Get the fare total
  double? get fareTotal {
    if (fareBreakdown != null) {
      return fareBreakdown!.total;
    }
    final fare = ride?['estimated_fare'];
    if (fare is num) {
      return fare.toDouble();
    }
    return null;
  }

  /// Create a copy with updated fields
  RideStatus copyWith({
    Map<String, dynamic>? ride,
    Map<String, dynamic>? payment,
    String? passengerNote,
    double? fareBasis,
    double? carpoolDiscountPctActual,
    String? weatherDesc,
    LatLng? driverLive,
    LatLng? myLive,
    DateTime? driverLastAt,
    DateTime? selfLastAt,
    FareBreakdown? fareBreakdown,
    double? platformFeeRate,
  }) {
    return RideStatus(
      ride: ride ?? this.ride,
      payment: payment ?? this.payment,
      passengerNote: passengerNote ?? this.passengerNote,
      fareBasis: fareBasis ?? this.fareBasis,
      carpoolDiscountPctActual: carpoolDiscountPctActual ?? this.carpoolDiscountPctActual,
      weatherDesc: weatherDesc ?? this.weatherDesc,
      driverLive: driverLive ?? this.driverLive,
      myLive: myLive ?? this.myLive,
      driverLastAt: driverLastAt ?? this.driverLastAt,
      selfLastAt: selfLastAt ?? this.selfLastAt,
      fareBreakdown: fareBreakdown ?? this.fareBreakdown,
      platformFeeRate: platformFeeRate ?? this.platformFeeRate,
    );
  }

  /// Create RideStatus from a Supabase row
  factory RideStatus.fromRow(Map<String, dynamic> row) {
    return RideStatus(
      ride: row,
      payment: row['payment'] as Map<String, dynamic>?,
      passengerNote: row['passenger_note'] as String?,
    );
  }

  @override
  String toString() => 'RideStatus(status: $status, isActive: $isActive)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideStatus &&
          runtimeType == other.runtimeType &&
          passengerId == other.passengerId;

  @override
  int get hashCode => passengerId.hashCode;
}

/// Enum for ride status types
enum RideStatusType {
  unknown,
  pending,
  matched,
  accepted,
  enRoute,
  pickedUp,
  droppedOff,
  completed,
  cancelled,
  declined,
}

/// Extension for RideStatusType to get display text
extension RideStatusTypeExtension on RideStatusType {
  String get displayName {
    switch (this) {
      case RideStatusType.pending:
        return 'Pending';
      case RideStatusType.matched:
        return 'Matched';
      case RideStatusType.accepted:
        return 'Accepted';
      case RideStatusType.enRoute:
        return 'En Route';
      case RideStatusType.pickedUp:
        return 'Picked Up';
      case RideStatusType.droppedOff:
        return 'Dropped Off';
      case RideStatusType.completed:
        return 'Completed';
      case RideStatusType.cancelled:
        return 'Cancelled';
      case RideStatusType.declined:
        return 'Declined';
      default:
        return 'Unknown';
    }
  }

  String get actionText {
    switch (this) {
      case RideStatusType.pending:
        return 'Finding driver...';
      case RideStatusType.matched:
        return 'Driver found!';
      case RideStatusType.accepted:
        return 'Driver en route';
      case RideStatusType.enRoute:
        return 'Almost there!';
      case RideStatusType.pickedUp:
        return 'Heading to destination';
      case RideStatusType.droppedOff:
        return 'Arrived!';
      case RideStatusType.completed:
        return 'Trip completed';
      case RideStatusType.cancelled:
        return 'Trip cancelled';
      case RideStatusType.declined:
        return 'Request declined';
      default:
        return 'Processing...';
    }
  }

  bool get isFinal =>
      this == RideStatusType.completed ||
      this == RideStatusType.cancelled ||
      this == RideStatusType.declined;
}
