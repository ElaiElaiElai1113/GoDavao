// lib/core/fare_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/osrm_service.dart';

class FareRules {
  /// Flag-down (peso)
  final double baseFare;

  /// Per kilometer (peso/km)
  final double perKm;

  /// Per minute (peso/min)
  final double perMin;

  /// Minimum charge before surcharges
  final double minFare;

  /// Fixed fee added once (e.g., booking)
  final double bookingFee;

  /// Nighttime surcharge percentage (0.15 = 15%)
  final double nightSurchargePct;

  /// Night starts at this hour (0-23)
  final int nightStartHour;

  /// Night ends **before** this hour (exclusive, 0-23). e.g., 5 => up to 4:59
  final int nightEndHour;

  /// Default platform fee rate (0..1)
  final double defaultPlatformFeeRate;

  /// Surge clamp
  final double minSurgeMultiplier;
  final double maxSurgeMultiplier;

  /// Carpool discount table by unique riders (1..N) -> pct (0..1)
  /// e.g., {2: 0.06, 3: 0.12, 4: 0.20}
  final Map<int, double> carpoolDiscountByPax;

  const FareRules({
    this.baseFare = 25.0,
    this.perKm = 14.0,
    this.perMin = 0.8,
    this.minFare = 70.0,
    this.bookingFee = 5.0,
    this.nightSurchargePct = 0.15,
    this.nightStartHour = 21,
    this.nightEndHour = 5,
    this.defaultPlatformFeeRate = 0.0,
    this.minSurgeMultiplier = 0.7,
    this.maxSurgeMultiplier = 2.0,
    this.carpoolDiscountByPax = const <int, double>{
      // 1 rider => 0% (implicit)
      2: 0.06,
      3: 0.12,
      4: 0.20,
      5: 0.25,
    },
  });
}

class FareBreakdown {
  final double distanceKm;
  final double durationMin;

  /// Base+distance+time+booking (after min-fare)
  final double subtotal;

  /// Peso amount added for night surcharge
  final double nightSurcharge;

  /// Surge used (clamped)
  final double surgeMultiplier;

  /// Seats billed (>=1). Seat count multiplies price; discount is *carpool-based*, not per seat.
  final int seatsBilled;

  /// Unique riders sharing (carpool participants)
  final int carpoolPassengers;

  /// Discount pct applied based on carpool size (0..1)
  final double carpoolDiscountPct;

  /// Final passenger total (rounded to peso)
  final double total;

  /// Platform & driver (2 decimals)
  final double platformFee;
  final double driverTake;

  const FareBreakdown({
    required this.distanceKm,
    required this.durationMin,
    required this.subtotal,
    required this.nightSurcharge,
    required this.surgeMultiplier,
    required this.seatsBilled,
    required this.carpoolPassengers,
    required this.carpoolDiscountPct,
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
    'carpool_passengers': carpoolPassengers,
    'carpool_discount_pct': carpoolDiscountPct,
    'total': total,
    'platform_fee': platformFee,
    'driver_take': driverTake,
  };
}

class FareService {
  final FareRules rules;
  FareService({this.rules = const FareRules()});

  // -------- Public APIs --------

  /// End-to-end estimate from coordinates (OSRM with Haversine fallback)
  Future<FareBreakdown> estimate({
    required LatLng pickup,
    required LatLng destination,
    DateTime? when,
    int seats = 1,
    int carpoolPassengers = 1,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) async {
    final (km, mins) = await _distanceAndTime(pickup, destination);
    return estimateForDistance(
      distanceKm: km,
      durationMin: mins,
      when: when,
      seats: seats,
      carpoolPassengers: carpoolPassengers,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
    );
  }

  /// Use this when you already have distance/time (e.g., partial segment).
  FareBreakdown estimateForDistance({
    required double distanceKm,
    required double durationMin,
    DateTime? when,
    int seats = 1,
    int carpoolPassengers = 1,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) {
    final now = when ?? DateTime.now();

    // 1) Baseline subtotal
    double subtotal =
        rules.baseFare +
        (rules.perKm * distanceKm) +
        (rules.perMin * durationMin) +
        rules.bookingFee;

    subtotal = _max(subtotal, rules.minFare);

    // 2) Night surcharge in pesos
    final night = _isNight(now);
    final nightSurcharge = night ? subtotal * rules.nightSurchargePct : 0.0;

    // 3) Surge
    final clampSurge = _clamp(
      surgeMultiplier,
      rules.minSurgeMultiplier,
      rules.maxSurgeMultiplier,
    );

    // 4) Seats billed (no per-seat discount; discount is carpool-based)
    final seatsBilled = _max(seats.toDouble(), 1).toInt();

    // 5) Carpool discount pct based on unique riders
    final pax = carpoolPassengers < 1 ? 1 : carpoolPassengers;
    final carpoolDiscountPct = rules.carpoolDiscountByPax[pax] ?? 0.0;

    // Compose price then apply discount
    final raw = (subtotal + nightSurcharge) * clampSurge * seatsBilled;
    final discounted = raw * (1.0 - carpoolDiscountPct);

    // Passenger total rounded to peso first
    final total = _roundPeso(discounted);

    // Platform & driver (2dp)
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
      carpoolPassengers: pax,
      carpoolDiscountPct: _round2(carpoolDiscountPct),
      total: total,
      platformFee: platformFee,
      driverTake: driverTake,
    );
  }

  // -------- Internals --------

  Future<(double km, double mins)> _distanceAndTime(
    LatLng from,
    LatLng to,
  ) async {
    try {
      final d = await fetchOsrmRouteDetailed(start: from, end: to);
      final km = d.distanceMeters / 1000.0;
      final mins = d.durationSeconds / 60.0;
      if (km > 0) return (km, _max(mins, 1.0));
    } catch (_) {
      // fall through
    }
    final km = _haversineKm(from, to);
    const avgKmh = 22.0; // fallback city speed
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
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  double _deg2rad(double d) => d * pi / 180.0;

  /// Treat `nightEndHour` as exclusive to avoid boundary double-charge.
  bool _isNight(DateTime now) {
    final h = now.hour;
    if (rules.nightStartHour < rules.nightEndHour) {
      // same-day window (e.g., 18..21)
      return h >= rules.nightStartHour && h < rules.nightEndHour;
    } else {
      // spans midnight (e.g., 21..5)
      return h >= rules.nightStartHour || h < rules.nightEndHour;
    }
  }

  // rounding + math helpers
  double _round(double v, int places) =>
      double.parse(v.toStringAsFixed(places));
  double _round2(double v) => _round(v, 2);
  double _roundPeso(double v) => v.roundToDouble();
  double _max(double a, double b) => a > b ? a : b;
  double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}
