// lib/core/fare_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/osrm_service.dart';

/// Pricing rules
class FareRules {
  final double baseFare; // flag-down
  final double perKm; // per kilometer
  final double perMin; // per minute
  final double minFare; // minimum before surcharges
  final double bookingFee; // fixed booking fee
  final double nightSurchargePct; // e.g., 0.15 = 15%
  final int nightStartHour; // 0-23
  final int nightEndHour; // exclusive (0-23)
  final double defaultPlatformFeeRate;
  final double perSeatDiscount; // pooled trips discount
  final double minSurgeMultiplier;
  final double maxSurgeMultiplier;

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
    this.perSeatDiscount = 0.0,
    this.minSurgeMultiplier = 0.7,
    this.maxSurgeMultiplier = 2.0,
  });
}

/// Detailed breakdown for receipts
class FareBreakdown {
  final double distanceKm;
  final double durationMin;
  final double subtotal;
  final double nightSurcharge;
  final double surgeMultiplier;
  final int seatsBilled;
  final double seatDiscountPct;
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
    required this.seatDiscountPct,
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
    'seat_discount_pct': seatDiscountPct,
    'total': total,
    'platform_fee': platformFee,
    'driver_take': driverTake,
  };
}

/// Fare engine
class FareService {
  final FareRules rules;
  FareService({this.rules = const FareRules()});

  // --- Main entrypoint using coordinates ---
  Future<FareBreakdown> estimate({
    required LatLng pickup,
    required LatLng destination,
    DateTime? when,
    int seats = 1,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) async {
    final (km, mins) = await _distanceAndTime(pickup, destination);
    return estimateForDistance(
      distanceKm: km,
      durationMin: mins,
      when: when,
      seats: seats,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
    );
  }

  // --- Use if you already know segment distance/time ---
  FareBreakdown estimateForDistance({
    required double distanceKm,
    required double durationMin,
    DateTime? when,
    int seats = 1,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) {
    final now = when ?? DateTime.now();

    // 1) Subtotal
    double subtotal =
        rules.baseFare +
        (rules.perKm * distanceKm) +
        (rules.perMin * durationMin) +
        rules.bookingFee;
    subtotal = _max(subtotal, rules.minFare);

    // 2) Night surcharge
    final night = _isNight(now);
    final nightSurcharge = night ? subtotal * rules.nightSurchargePct : 0.0;

    // 3) Surge
    final clampSurge = _clamp(
      surgeMultiplier,
      rules.minSurgeMultiplier,
      rules.maxSurgeMultiplier,
    );

    // 4) Seats
    final seatsBilled = _max(seats.toDouble(), 1).toInt();
    final seatDiscountPct = (seatsBilled > 1) ? rules.perSeatDiscount : 0.0;
    final seatFactor = seatsBilled * (1.0 - seatDiscountPct);

    // 5) Raw total
    final raw = (subtotal + nightSurcharge) * clampSurge * seatFactor;
    final total = _roundPeso(raw);

    // 6) Platform/driver
    final feeRate = _clamp(
      (platformFeeRate ?? rules.defaultPlatformFeeRate),
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
      seatDiscountPct: _round2(seatDiscountPct),
      total: total,
      platformFee: platformFee,
      driverTake: driverTake,
    );
  }

  // --- Convenience: if you measured meters/seconds already ---
  FareBreakdown estimateFromMeters({
    required double meters,
    double? seconds,
    double avgKmh = 22.0,
    DateTime? when,
    int seats = 1,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) {
    final km = meters / 1000.0;
    final mins = seconds != null ? (seconds / 60.0) : ((km / avgKmh) * 60.0);
    return estimateForDistance(
      distanceKm: km,
      durationMin: _max(mins, 1.0),
      when: when,
      seats: seats,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
    );
  }

  // --- NEW: adapter for polyline segment measurement ---
  FareBreakdown estimateFromSegment({
    required ({double km, double mins}) segment,
    DateTime? when,
    int seats = 1,
    double? platformFeeRate,
    double surgeMultiplier = 1.0,
  }) {
    return estimateForDistance(
      distanceKm: segment.km,
      durationMin: segment.mins,
      when: when,
      seats: seats,
      platformFeeRate: platformFeeRate,
      surgeMultiplier: surgeMultiplier,
    );
  }

  // --- internals ---
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
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
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
