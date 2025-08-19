import 'dart:math';

class FareBreakdown {
  final double km;
  final double minutes;

  final double baseFare;
  final double perKmComponent;
  final double perMinComponent;
  final double bookingFee;
  final double nightSurcharge;
  final double total;
  final bool isNight;

  const FareBreakdown({
    required this.km,
    required this.minutes,
    required this.baseFare,
    required this.perKmComponent,
    required this.perMinComponent,
    required this.bookingFee,
    required this.nightSurcharge,
    required this.total,
    required this.isNight,
  });
}

class FareCalculator {
  // Keep these in sync with your app’s policy
  static const double baseFare = 50.0;
  static const double perKm = 10.0;
  static const double perMin = 2.0;
  static const double bookingFee = 5.0;
  static const double minFare = 70.0;

  // Night rules
  static const double nightPct = 0.15;
  static const int nightStartHour = 23; // inclusive
  static const int nightEndHour = 5; // inclusive

  static bool _isNight(DateTime now) {
    final h = now.hour;
    return (h >= nightStartHour) || (h <= nightEndHour);
  }

  static FareBreakdown estimate({
    required double km,
    required double minutes,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();

    final perKmComponent = perKm * km;
    final perMinComponent = perMin * max(minutes, 1.0);

    double subtotal = baseFare + perKmComponent + perMinComponent + bookingFee;
    subtotal = max(subtotal, minFare);

    final bool night = _isNight(n);
    final nightSurcharge = night ? subtotal * nightPct : 0.0;

    final total = (subtotal + nightSurcharge);

    return FareBreakdown(
      km: double.parse(km.toStringAsFixed(2)),
      minutes: double.parse(minutes.toStringAsFixed(0)),
      baseFare: baseFare,
      perKmComponent: perKmComponent,
      perMinComponent: perMinComponent,
      bookingFee: bookingFee,
      nightSurcharge: nightSurcharge,
      total: total.roundToDouble(),
      isNight: night,
    );
  }
}
