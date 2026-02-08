// lib/core/fare_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/osrm_service.dart';

enum PricingMode { shared, sharedDistance, groupFlat, pakyaw }

/// Represents a passenger in a shared ride with their distance traveled.
///
/// Used as input to [estimateSharedDistanceFare] to calculate distance-proportional
/// fare splitting.
class SharedPassenger {
  /// Unique identifier for the passenger
  final String id;
  /// Distance this passenger travels along the route in kilometers
  final double distanceKm;

  const SharedPassenger({
    required this.id,
    required this.distanceKm,
  });
}

/// Fare calculation rules for GoDavao rides.
///
/// Pricing formula:
/// ```dart
/// subtotal = baseFare + (perKm × distanceKm) + (perMin × durationMin) + bookingFee
/// subtotal = max(subtotal, minFare)
///
/// nightSurcharge = subtotal × nightSurchargePct (if night hours)
///
/// raw = (subtotal + nightSurcharge) × surgeMultiplier × seatsBilled
///
/// Apply mode multipliers:
///   - groupFlat: × 1.10
///   - pakyaw: × 1.20
///
/// Apply carpool discount (except for groupFlat):
///   raw = raw × (1 - carpoolDiscountPct)
///
/// total = round(raw)
/// platformFee = total × platformFeeRate
/// driverTake = total - platformFee
/// ```
class FareRules {
  /// Base starting fare for all rides (₱25)
  final double baseFare;
  /// Rate per kilometer traveled (₱14/km)
  final double perKm;
  /// Rate per minute of travel time (₱0.80/min)
  final double perMin;
  /// Minimum fare regardless of distance (₱70)
  final double minFare;
  /// One-time booking fee (₱5)
  final double bookingFee;
  /// Additional percentage charge for night rides (15%)
  final double nightSurchargePct;
  /// Night surcharge start hour (21:00 / 9 PM)
  final int nightStartHour;
  /// Night surcharge end hour (05:00 / 5 AM)
  final int nightEndHour;
  /// Platform fee percentage of total fare (15%)
  final double defaultPlatformFeeRate;
  /// Minimum surge multiplier during low demand (0.7×)
  final double minSurgeMultiplier;
  /// Maximum surge multiplier during high demand (2.0×)
  final double maxSurgeMultiplier;
  /// Carpool discounts based on total seats filled
  /// Key = number of seats, Value = discount percentage
  final Map<int, double> carpoolDiscountBySeats;
  /// Group flat mode multiplier (1.10×)
  final double groupFlatMultiplier;
  /// Pakyaw (private) mode multiplier (1.20×)
  final double pakyawMultiplier;

  const FareRules({
    this.baseFare = 25.0,
    this.perKm = 14.0,
    this.perMin = 0.8,
    this.minFare = 70.0,
    this.bookingFee = 5.0,
    this.nightSurchargePct = 0.15,
    this.nightStartHour = 21,
    this.nightEndHour = 5,
    this.defaultPlatformFeeRate = 0.15,
    this.minSurgeMultiplier = 0.7,
    this.maxSurgeMultiplier = 2.0,
    this.carpoolDiscountBySeats = const {2: 0.06, 3: 0.12, 4: 0.20, 5: 0.25},
    this.groupFlatMultiplier = 1.10,
    this.pakyawMultiplier = 1.20,
  });
}

/// Individual fare breakdown for a single passenger in a shared ride.
///
/// Used in distance-proportional pricing to show how much each passenger
/// contributes based on their traveled distance.
class PassengerFare {
  /// Unique identifier for the passenger
  final String passengerId;
  /// Distance this passenger traveled in kilometers
  final double distanceKm;
  /// This passenger's share of the route fare (before platform fee)
  final double fareShare;
  /// Platform fee for this passenger
  final double platformFee;
  /// Total amount this passenger pays (fareShare + platformFee)
  final double total;

  const PassengerFare({
    required this.passengerId,
    required this.distanceKm,
    required this.fareShare,
    required this.platformFee,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
    'passenger_id': passengerId,
    'distance_km': distanceKm,
    'fare_share': fareShare,
    'platform_fee': platformFee,
    'total': total,
  };
}

/// Breakdown of fare distribution for a shared ride with multiple passengers.
///
/// Used by [estimateSharedDistanceFare] to return the complete pricing details
/// when using distance-proportional pricing.
class SharedFareBreakdown {
  /// Total distance of the route in kilometers
  final double totalRouteDistanceKm;
  /// Estimated travel time in minutes
  final double durationMin;
  /// Total fare collected from all passengers (before platform fees)
  final double totalFare;
  /// Total platform fee collected from all passengers
  final double totalPlatformFee;
  /// Total driver earnings after platform fees
  final double totalDriverTake;
  /// Individual fare breakdown for each passenger
  final List<PassengerFare> passengerFares;
  /// Pricing mode used (should be [PricingMode.sharedDistance])
  final PricingMode mode;

  const SharedFareBreakdown({
    required this.totalRouteDistanceKm,
    required this.durationMin,
    required this.totalFare,
    required this.totalPlatformFee,
    required this.totalDriverTake,
    required this.passengerFares,
    required this.mode,
  });

  Map<String, dynamic> toMap() => {
    'total_route_distance_km': totalRouteDistanceKm,
    'duration_min': durationMin,
    'total_fare': totalFare,
    'total_platform_fee': totalPlatformFee,
    'total_driver_take': totalDriverTake,
    'passenger_fares': passengerFares.map((p) => p.toMap()).toList(),
    'mode': mode.name,
  };
}

class FareBreakdown {
  final double distanceKm;
  final double durationMin;
  final double subtotal;
  final double nightSurcharge;
  final double surgeMultiplier;
  final int seatsBilled;
  final int carpoolSeats;
  final double carpoolDiscountPct;
  final PricingMode mode;
  final double total;
  final double platformFee;
  final double driverTake;

  const FareBreakdown({
    required this.distanceKm,
    required this.durationMin,
    required this.subtotal,
    required this.nightSurcharge,
    required this.surgeMultiplier,
    required this.seatsBilled,
    required this.carpoolSeats,
    required this.carpoolDiscountPct,
    required this.mode,
    required this.total,
    required this.platformFee,
    required this.driverTake,
  });

  Map<String, dynamic> toMap() => {
    'distance_km': distanceKm,
    'duration_min': durationMin,
    'subtotal': subtotal,
    'night_surcharge': nightSurcharge,
    'surge_multiplier': surgeMultiplier,
    'seats_billed': seatsBilled,
    'carpool_seats': carpoolSeats,
    'carpool_discount_pct': carpoolDiscountPct,
    'mode': mode.name,
    'total': total,
    'platform_fee': platformFee,
    'driver_take': driverTake,
  };
}

class FareService {
  final FareRules rules;
  FareService({this.rules = const FareRules()});

  Future<FareBreakdown> estimate({
    required LatLng pickup,
    required LatLng destination,
    DateTime? when,
    int seats = 1,
    int? carpoolSeats,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
    PricingMode mode = PricingMode.shared,
  }) async {
    final (km, mins) = await _distanceAndTime(pickup, destination);
    return estimateForDistance(
      distanceKm: km,
      durationMin: mins,
      when: when,
      seats: seats,
      carpoolSeats: carpoolSeats,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
      mode: mode,
    );
  }

  FareBreakdown estimateForDistance({
    required double distanceKm,
    required double durationMin,
    DateTime? when,
    int seats = 1,
    int? carpoolSeats,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
    PricingMode mode = PricingMode.shared,
  }) {
    final now = when ?? DateTime.now();

    double subtotal =
        rules.baseFare +
        (rules.perKm * distanceKm) +
        (rules.perMin * durationMin) +
        rules.bookingFee;
    subtotal = _max(subtotal, rules.minFare);

    final night = _isNight(now);
    final nightSurcharge = night ? subtotal * rules.nightSurchargePct : 0.0;

    final clampSurge = _clamp(
      surgeMultiplier,
      rules.minSurgeMultiplier,
      rules.maxSurgeMultiplier,
    );

    int seatsBilled;
    int seatsForDiscount;
    double carpoolDiscountPct;

    if (mode == PricingMode.shared) {
      seatsBilled = _max(seats.toDouble(), 1).toInt();
      seatsForDiscount = _resolveSeatsForDiscount(carpoolSeats: carpoolSeats);
      carpoolDiscountPct = _lookupDiscountPct(seatsForDiscount);
    } else if (mode == PricingMode.groupFlat) {
      seatsBilled = 1;
      seatsForDiscount = _resolveSeatsForDiscount(carpoolSeats: carpoolSeats);
      carpoolDiscountPct = 0.0;
    } else {
      seatsBilled = _max(seats.toDouble(), 1).toInt();
      seatsForDiscount = _resolveSeatsForDiscount(carpoolSeats: carpoolSeats);
      carpoolDiscountPct = _lookupDiscountPct(seatsForDiscount);
    }

    double raw = (subtotal + nightSurcharge) * clampSurge * seatsBilled;

    if (mode == PricingMode.groupFlat) {
      raw = raw * rules.groupFlatMultiplier;
    } else if (mode == PricingMode.pakyaw) {
      raw = raw * rules.pakyawMultiplier;
    }

    if (mode != PricingMode.groupFlat) {
      raw = raw * (1.0 - carpoolDiscountPct);
    }

    final total = _roundPeso(raw);

    final feeRate = _clamp(
      platformFeeRate ?? rules.defaultPlatformFeeRate,
      0.0,
      1.0,
    );
    final platformFee = _round2(total * feeRate);
    final driverTake = _round2(total - platformFee);

    return FareBreakdown(
      distanceKm: _round(distanceKm, 2),
      durationMin: _round(durationMin, 0),
      subtotal: _round2(subtotal),
      nightSurcharge: _round2(nightSurcharge),
      surgeMultiplier: clampSurge,
      seatsBilled: seatsBilled,
      carpoolSeats: seatsForDiscount,
      carpoolDiscountPct: _round2(carpoolDiscountPct),
      mode: mode,
      total: total,
      platformFee: platformFee,
      driverTake: driverTake,
    );
  }

  /// Calculate proportional fares for shared rides based on distance traveled.
  ///
  /// This method implements distance-proportional pricing where passengers pay
  /// based on their actual usage of the route. The total route fare is calculated
  /// once, then split among passengers proportionally to their distance traveled.
  ///
  /// **Algorithm:**
  /// 1. Calculate total route fare using full route distance
  /// 2. Sum all passenger distances
  /// 3. For each passenger:
  ///    - Calculate their distance share: (their_distance / total_passenger_distance)
  ///    - Their fare = route_fare × distance_share
  ///    - Add platform fee to get their total
  ///
  /// **Example:**
  /// ```dart
  /// // Route: 10km, total fare = ₱500
  /// final passengers = [
  ///   SharedPassenger(id: 'A', distanceKm: 10.0), // Full route
  ///   SharedPassenger(id: 'B', distanceKm: 5.0),  // Half route
  /// ];
  ///
  /// // Passenger A: (10/15) × 500 = ₱333
  /// // Passenger B: (5/15) × 500 = ₱167
  /// // Total collected: ₱500 (equals route fare)
  /// ```
  ///
  /// **Key Benefits:**
  /// - Fair pricing: passengers pay proportionally to distance traveled
  /// - Driver revenue protection: total collected equals full route fare
  /// - Transparency: clear relationship between distance and cost
  Future<SharedFareBreakdown> estimateSharedDistanceFare({
    required LatLng routeStart,
    required LatLng routeEnd,
    required List<SharedPassenger> passengers,
    DateTime? when,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) async {
    final (totalKm, totalMins) = await _distanceAndTime(routeStart, routeEnd);

    // Calculate total route fare (based on full route distance)
    final baseFareBreakdown = estimateForDistance(
      distanceKm: totalKm,
      durationMin: totalMins,
      when: when,
      seats: 1, // Base fare for the route
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
      mode: PricingMode.shared,
    );

    // Calculate total passenger distance
    final totalPassengerKm = passengers.fold<double>(
      0.0,
      (sum, p) => sum + p.distanceKm,
    );

    // Calculate each passenger's fare proportionally
    final passengerFares = <PassengerFare>[];
    double totalFare = 0.0;
    double totalPlatformFee = 0.0;

    for (final passenger in passengers) {
      // Calculate this passenger's share of the route fare
      final distanceShare = totalPassengerKm > 0
          ? (passenger.distanceKm / totalPassengerKm)
          : (1.0 / passengers.length);

      final fareShare = _round2(baseFareBreakdown.total * distanceShare);
      final pFee = _round2(fareShare * (platformFeeRate ?? rules.defaultPlatformFeeRate));
      final pTotal = _roundPeso(fareShare + pFee);

      passengerFares.add(PassengerFare(
        passengerId: passenger.id,
        distanceKm: passenger.distanceKm,
        fareShare: fareShare,
        platformFee: pFee,
        total: pTotal,
      ));

      totalFare += pTotal;
      totalPlatformFee += pFee;
    }

    final totalDriverTake = _round2(totalFare - totalPlatformFee);

    return SharedFareBreakdown(
      totalRouteDistanceKm: _round(totalKm, 2),
      durationMin: _round(totalMins, 0),
      totalFare: totalFare,
      totalPlatformFee: totalPlatformFee,
      totalDriverTake: totalDriverTake,
      passengerFares: passengerFares,
      mode: PricingMode.sharedDistance,
    );
  }

  int _resolveSeatsForDiscount({required int? carpoolSeats}) {
    if (carpoolSeats != null && carpoolSeats > 0) return carpoolSeats;
    return 1;
  }

  double _lookupDiscountPct(int seatsForDiscount) {
    if (seatsForDiscount <= 1) return 0.0;
    double pct = 0.0;
    for (final e in rules.carpoolDiscountBySeats.entries) {
      if (e.key <= seatsForDiscount && e.value > pct) pct = e.value;
    }
    return pct;
  }

  Future<(double km, double mins)> _distanceAndTime(
    LatLng from,
    LatLng to,
  ) async {
    try {
      final d = await fetchOsrmRouteDetailed(start: from, end: to);
      final km = d.distanceMeters / 1000.0;
      final mins = d.durationSeconds / 60.0;
      if (km > 0) return (km, _max(mins, 1.0));
    } catch (_) {}
    final km = _haversineKm(from, to);
    const avgKmh = 22.0;
    final mins = (km / avgKmh) * 60.0;
    return (km, _max(mins, 1.0));
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    double dLat = _deg2rad(b.latitude - a.latitude);
    double dLon = _deg2rad(b.longitude - a.longitude);
    double lat1 = _deg2rad(a.latitude);
    double lat2 = _deg2rad(b.latitude);
    final h =
        sin(dLat / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2) +
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  double _deg2rad(double d) => d * pi / 180.0;
  bool _isNight(DateTime now) {
    final h = now.hour;
    if (rules.nightStartHour < rules.nightEndHour) {
      return h >= rules.nightStartHour && h < rules.nightEndHour;
    } else {
      return h >= rules.nightStartHour || h < rules.nightEndHour;
    }
  }

  double _round(double v, int places) =>
      double.parse(v.toStringAsFixed(places));
  double _round2(double v) => _round(v, 2);
  double _roundPeso(double v) => v.roundToDouble();
  double _max(double a, double b) => a > b ? a : b;
  double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}
