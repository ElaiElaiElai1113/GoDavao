// lib/core/fare_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:godavao/core/osrm_service.dart';

class FareRules {
  final double baseFare; // flag-down
  final double perKm; // per kilometer
  final double perMin; // per minute (from OSRM duration)
  final double minFare; // minimum fare
  final double bookingFee; // fixed fee
  final double nightSurchargePct; // e.g., 0.15 = 15% more
  final int nightStartHour; // 21 means 9 PM
  final int nightEndHour; // 5 means 5 AM

  const FareRules({
    this.baseFare = 25.0,
    this.perKm = 14.0,
    this.perMin = 0.8,
    this.minFare = 70.0,
    this.bookingFee = 5.0,
    this.nightSurchargePct = 0.15,
    this.nightStartHour = 21,
    this.nightEndHour = 5,
  });
}

class FareBreakdown {
  final double distanceKm;
  final double durationMin;
  final double subtotal;
  final double surcharge;
  final double total;

  const FareBreakdown({
    required this.distanceKm,
    required this.durationMin,
    required this.subtotal,
    required this.surcharge,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
    'distance_km': distanceKm,
    'duration_min': durationMin,
    'subtotal': subtotal,
    'surcharge': surcharge,
    'total': total,
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

  bool _isNight(DateTime now) {
    final h = now.hour;
    // window may wrap midnight
    if (rules.nightStartHour <= rules.nightEndHour) {
      return h >= rules.nightStartHour && h <= rules.nightEndHour;
    } else {
      return h >= rules.nightStartHour || h <= rules.nightEndHour;
    }
  }

  Future<FareBreakdown> estimate({
    required LatLng pickup,
    required LatLng destination,
    DateTime? when,
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
    final total = subtotal + surcharge;

    // Round to nearest peso (₱)
    double roundPeso(double x) => x.roundToDouble();

    return FareBreakdown(
      distanceKm: double.parse(km.toStringAsFixed(2)),
      durationMin: double.parse(mins.toStringAsFixed(0)),
      subtotal: double.parse(subtotal.toStringAsFixed(2)),
      surcharge: double.parse(surcharge.toStringAsFixed(2)),
      total: roundPeso(total),
    );
  }
}
