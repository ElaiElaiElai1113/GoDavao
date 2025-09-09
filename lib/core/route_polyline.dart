import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  final List<List<num>> decoded = gpa.decodePolyline(encoded);
  if (decoded.isEmpty) return null;

  final points = decoded
      .map((e) => LatLng(e[0].toDouble(), e[1].toDouble()))
      .toList(growable: false);

  return Polyline(points: points, strokeWidth: strokeWidth);
}
