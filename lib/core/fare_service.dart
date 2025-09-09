// lib/core/fare_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/osrm_service.dart';

class FareRules {
  /// Flag-down
  final double baseFare;

  /// Per kilometer
  final double perKm;

  /// Per minute (from OSRM duration)
  final double perMin;

  /// Minimum charge before surcharges
  final double minFare;

  /// Fixed fee added once (e.g., booking)
  final double bookingFee;

  /// Nighttime surcharge percentage (0.15 = 15%)
  final double nightSurchargePct;

  /// Night starts at this hour (0-23)
  final int nightStartHour;

  /// Night ends **before** this hour (exclusive, 0-23). e.g., 5 means up to 4:59
  final int nightEndHour;

  const FareRules({
    this.baseFare = 25.0,
    this.perKm = 14.0,
    this.perMin = 0.8,
    this.minFare = 70.0,
    this.bookingFee = 5.0,
    this.nightSurchargePct = 0.15,
    this.nightStartHour = 21, // 9 PM
    this.nightEndHour = 5, // until 4:59 AM
  });
}

class FareBreakdown {
  final double distanceKm;
  final double durationMin;

  /// Base+distance+time+booking (after min-fare applied, before surcharges)
  final double subtotal;

  /// Night surcharge amount
  final double surcharge;

  /// Passenger pays (rounded to peso)
  final double total;

  /// Optional: platform fee amount (2 decimals)
  final double platformFee;

  /// Optional: what the driver takes home (2 decimals)
  final double driverTake;

  const FareBreakdown({
    required this.distanceKm,
    required this.durationMin,
    required this.subtotal,
    required this.surcharge,
    required this.total,
    this.platformFee = 0.0,
    this.driverTake = 0.0,
  });

  Map<String, dynamic> toMap() => {
    'distance_km': distanceKm,
    'duration_min': durationMin,
    'subtotal': subtotal,
    'surcharge': surcharge,
    'total': total,
    'platform_fee': platformFee,
    'driver_take': driverTake,
  };
}

class FareService {
  final FareRules rules;
  FareService({this.rules = const FareRules()});

  Future<(double km, double mins)> _distanceAndTime(
    LatLng from,
    LatLng to,
  ) async {
    try {
      final d = await fetchOsrmRouteDetailed(start: from, end: to);
      final km = (d.distanceMeters) / 1000.0;
      final mins = (d.durationSeconds) / 60.0;
      if (km > 0) return (km, max(mins, 1.0));
    } catch (_) {
      // fall through to Haversine
    }
    final km = _haversineKm(from, to);
    // naive city avg speed for fallback
    const avgKmh = 22.0;
    final mins = (km / avgKmh) * 60.0;
    return (km, max(mins, 1.0));
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

  /// Treat `nightEndHour` as exclusive to avoid double-charging at the boundary.
  bool _isNight(DateTime now) {
    final h = now.hour;
    if (rules.nightStartHour < rules.nightEndHour) {
      // e.g., 18..21 (same day window)
      return h >= rules.nightStartHour && h < rules.nightEndHour;
    } else {
      // spans midnight (e.g., 21..5)
      return h >= rules.nightStartHour || h < rules.nightEndHour;
    }
  }

  /// Estimate fare, optionally including platform fee & driver take.
  ///
  /// [platformFeeRate] should be between 0 and 1 (e.g., 0.18 = 18%).
  /// You can fetch it from `app_settings.platform_fee_rate` and pass here.
  Future<FareBreakdown> estimate({
    required LatLng pickup,
    required LatLng destination,
    DateTime? when,
    double? platformFeeRate, // optional; if null, fee=0 and driverTake=total
  }) async {
    final (km, mins) = await _distanceAndTime(pickup, destination);

    double subtotal =
        rules.baseFare +
        (rules.perKm * km) +
        (rules.perMin * mins) +
        rules.bookingFee;

    subtotal = max(subtotal, rules.minFare);

    final now = when ?? DateTime.now();
    final surcharge = _isNight(now) ? subtotal * rules.nightSurchargePct : 0.0;

    // Passenger total: rounded to the nearest peso
    final rawTotal = subtotal + surcharge;
    final passengerTotal = _roundPeso(rawTotal);

    // Platform fee + driver take (rounded to 2 decimals for display/accounting)
    final rate =
        (platformFeeRate != null && platformFeeRate > 0)
            ? platformFeeRate.clamp(0.0, 1.0)
            : 0.0;

    final platformFee = _round2(passengerTotal * rate);
    final driverTake = _round2(passengerTotal - platformFee);

    return FareBreakdown(
      distanceKm: _round(km, 2),
      durationMin: _round(mins, 0),
      subtotal: _round2(subtotal),
      surcharge: _round2(surcharge),
      total: passengerTotal,
      platformFee: platformFee,
      driverTake: driverTake,
    );
  }

  // --- rounding helpers ---
  double _round(double v, int places) =>
      double.parse(v.toStringAsFixed(places));
  double _round2(double v) => _round(v, 2);
  double _roundPeso(double v) => v.roundToDouble();
}
