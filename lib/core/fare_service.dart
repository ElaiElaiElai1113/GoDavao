// lib/core/fare_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/osrm_service.dart';

enum PricingMode { shared, sharedDistance, groupFlat, pakyaw }

class SharedPassenger {
  final String id;
  final double distanceKm;

  const SharedPassenger({
    required this.id,
    required this.distanceKm,
  });
}

class FareRules {
  final double baseFare;
  final double perKm;
  final double perMin;
  final double minFare;
  final double bookingFee;
  final double nightSurchargePct;
  final int nightStartHour;
  final int nightEndHour;
  final double defaultPlatformFeeRate;
  final double minSurgeMultiplier;
  final double maxSurgeMultiplier;
  final Map<int, double> carpoolDiscountBySeats;
  final double groupFlatMultiplier;
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

class PassengerFare {
  final String passengerId;
  final double distanceKm;
  final double fareShare;
  final double platformFee;
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

class SharedFareBreakdown {
  final double totalRouteDistanceKm;
  final double durationMin;
  final double totalFare;
  final double totalPlatformFee;
  final double totalDriverTake;
  final List<PassengerFare> passengerFares;
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

  /// Calculate proportional fares for shared rides based on distance.
  ///
  /// Passengers split the total route fare proportionally based on their
  /// individual distance traveled along the route.
  ///
  /// Example:
  /// - Route: 10km, total fare = ₱500
  /// - Passenger A: 10km (pays ₱333)
  /// - Passenger B: 5km (pays ₱167)
  /// - Total: ₱500
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
