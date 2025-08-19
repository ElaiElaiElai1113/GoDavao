// lib/features/rides/data/fare_calculator.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';

class FareBreakdown {
  final double km;
  final double minutes;
  final double baseFare;
  final double perKmComponent;
  final double perMinComponent;
  final double bookingFee;
  final double nightSurcharge;
  final double subtotalBeforeNight;
  final double total;

  const FareBreakdown({
    required this.km,
    required this.minutes,
    required this.baseFare,
    required this.perKmComponent,
    required this.perMinComponent,
    required this.bookingFee,
    required this.nightSurcharge,
    required this.subtotalBeforeNight,
    required this.total,
  });
}

class FareCalculator {
  // You can make these configurable (e.g., remote config / Supabase table)
  static const double baseFare = 50.0;
  static const double perKm = 10.0;
  static const double perMin = 2.0;
  static const double minFare = 70.0;
  static const double bookingFee = 5.0;

  // Night surcharge
  static const double nightPct = 0.15;
  static const int nightStartHour = 23; // 11 PM
  static const int nightEndHour = 5; // 5 AM

  /// Returns true if the given time is considered "night" for surcharge.
  static bool isNight(DateTime now) {
    final h = now.hour;
    return (h >= nightStartHour) || (h <= nightEndHour);
  }

  /// Clean Haversine distance (km) for fallback when OSRM is unavailable.
  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0; // Earth radius (km)
    double deg2rad(double d) => d * pi / 180.0;

    final dLat = deg2rad(b.latitude - a.latitude);
    final dLon = deg2rad(b.longitude - a.longitude);
    final lat1 = deg2rad(a.latitude);
    final lat2 = deg2rad(b.latitude);

    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  /// Core fare computation given km & minutes.
  static FareBreakdown estimate({
    required double km,
    required double minutes,
    DateTime? now,
  }) {
    final _now = now ?? DateTime.now();

    // Components
    final kmCost = perKm * km;
    final minCost = perMin * minutes;
    double subtotal = baseFare + kmCost + minCost + bookingFee;

    // Minimum fare rule
    if (subtotal < minFare) {
      subtotal = minFare;
    }

    // Night surcharge
    final nightFee = isNight(_now) ? subtotal * nightPct : 0.0;

    final total = subtotal + nightFee;

    return FareBreakdown(
      km: double.parse(km.toStringAsFixed(2)),
      minutes: double.parse(minutes.toStringAsFixed(0)),
      baseFare: baseFare,
      perKmComponent: double.parse(kmCost.toStringAsFixed(2)),
      perMinComponent: double.parse(minCost.toStringAsFixed(2)),
      bookingFee: bookingFee,
      nightSurcharge: double.parse(nightFee.toStringAsFixed(2)),
      subtotalBeforeNight: double.parse(subtotal.toStringAsFixed(2)),
      total: total.roundToDouble(),
    );
  }
}
