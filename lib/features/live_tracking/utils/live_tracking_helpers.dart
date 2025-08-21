import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class LiveTrackingHelpers {
  static const double _earthRadiusM = 6371000.0;

  static double haversineMeters(LatLng a, LatLng b) {
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return _earthRadiusM * c;
  }

  static double bearingDeg(LatLng a, LatLng b) {
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    double brng = _rad2deg(math.atan2(y, x));
    brng = (brng + 360.0) % 360.0;
    return brng;
  }

  static LatLng lerp(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Simple moving-average smoothing for GPS jitter.
  /// window must be odd; if even, it will be rounded up to next odd.
  static List<LatLng> smoothMovingAverage(
    List<LatLng> points, {
    int window = 5,
  }) {
    if (points.length <= 2 || window <= 1) return points;
    if (window % 2 == 0) window += 1;
    final half = window ~/ 2;

    final out = <LatLng>[];
    for (int i = 0; i < points.length; i++) {
      double la = 0, lo = 0;
      int cnt = 0;
      for (
        int j = math.max(0, i - half);
        j <= math.min(points.length - 1, i + half);
        j++
      ) {
        la += points[j].latitude;
        lo += points[j].longitude;
        cnt++;
      }
      out.add(LatLng(la / cnt, lo / cnt));
    }
    return out;
  }

  static Duration estimateEta({
    required double remainingMeters,
    required double speedMps,
    double fallbackSpeedMps = 8.0,
  }) {
    final v = speedMps > 0 ? speedMps : fallbackSpeedMps;
    final secs = (remainingMeters / v).clamp(1, 36000);
    return Duration(seconds: secs.toInt());
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;
  static double _rad2deg(double r) => r * 180.0 / math.pi;
}
