import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PolylineSnap {
  final LatLng point;
  // segmentIndex + t in [0, n-1], larger = further along the polyline
  final double progress;
  const PolylineSnap(this.point, this.progress);
}

Polyline? effectivePolylineFromRoute({
  required String? routeMode, // 'osrm' | 'manual' | null
  required String? routePolyline, // encoded
  required String? manualPolyline, // encoded
  double strokeWidth = 5,
}) {
  final encoded =
      (routeMode == 'manual')
          ? manualPolyline
          : routePolyline ?? manualPolyline; // fallback if mode is missing

  if (encoded == null || encoded.isEmpty) return null;

  final points = decodePolylinePoints(encoded);
  if (points.isEmpty) return null;

  return Polyline(points: points, strokeWidth: strokeWidth);
}

List<LatLng> decodePolylinePoints(String encoded) {
  final List<List<num>> decoded = gpa.decodePolyline(encoded);
  if (decoded.isEmpty) return const [];
  return decoded
      .map((e) => LatLng(e[0].toDouble(), e[1].toDouble()))
      .toList(growable: false);
}

PolylineSnap? snapToPolyline(LatLng point, List<LatLng> polyline) {
  if (polyline.length < 2) return null;

  double bestD = double.infinity;
  LatLng bestPoint = polyline.first;
  double bestProgress = 0.0;

  for (var i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];

    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = point.longitude, py = point.latitude;

    final vx = bx - ax, vy = by - ay;
    final wx = px - ax, wy = py - ay;

    final c1 = vx * wx + vy * wy;
    final c2 = vx * vx + vy * vy;

    double t;
    if (c2 == 0) {
      t = 0.0;
    } else if (c1 <= 0) {
      t = 0.0;
    } else if (c2 <= c1) {
      t = 1.0;
    } else {
      t = c1 / c2;
    }

    final proj = LatLng(ay + t * vy, ax + t * vx);
    final d = const Distance().as(LengthUnit.Meter, proj, point);
    if (d < bestD) {
      bestD = d;
      bestPoint = proj;
      bestProgress = i + t;
    }
  }

  return PolylineSnap(bestPoint, bestProgress);
}

double polylineDistanceBetweenProgress(
  List<LatLng> polyline,
  double startProgress,
  double endProgress,
) {
  if (polyline.length < 2) return 0.0;

  double a = startProgress;
  double b = endProgress;
  if (b < a) {
    final tmp = a;
    a = b;
    b = tmp;
  }

  final dist = const Distance();

  double prefixAt(double progress) {
    final idx = progress.floor().clamp(0, polyline.length - 2);
    final t = (progress - idx).clamp(0.0, 1.0);
    double sum = 0.0;

    for (var i = 0; i < idx; i++) {
      sum += dist.as(
        LengthUnit.Meter,
        polyline[i],
        polyline[i + 1],
      );
    }

    if (t > 0) {
      sum += dist.as(
            LengthUnit.Meter,
            polyline[idx],
            polyline[idx + 1],
          ) *
          t;
    }

    return sum;
  }

  final meters = prefixAt(b) - prefixAt(a);
  return meters / 1000.0;
}
