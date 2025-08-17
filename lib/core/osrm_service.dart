import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Configure your OSRM endpoint here if not running locally.
/// For production, set this to your public OSRM host, e.g. "https://osrm.your-domain.com".
const String? kOsrmOverrideBaseUrl = null; // e.g. "https://osrm.example.com"

String _defaultOsrmBaseUrl() {
  // Web builds must use the actual hostname
  if (kIsWeb) return 'http://localhost:5000';

  // Android emulator needs the special loopback
  if (defaultTargetPlatform == TargetPlatform.android)
    return 'http://10.0.2.2:5000';

  // iOS simulator / desktop
  return 'http://localhost:5000';
}

String getOsrmBaseUrl() => kOsrmOverrideBaseUrl ?? _defaultOsrmBaseUrl();

class OsrmRouteDetailed {
  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;

  OsrmRouteDetailed({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  Polyline toPolyline({Color color = Colors.blue, double width = 4}) {
    return Polyline(points: points, strokeWidth: width, color: color);
  }
}

/// Simple preview polyline (kept for compatibility)
Future<Polyline> fetchOsrmRoute({
  required LatLng start,
  required LatLng end,
  Color color = Colors.blue,
  double width = 4,
}) async {
  final d = await fetchOsrmRouteDetailed(start: start, end: end);
  return d.toPolyline(color: color, width: width);
}

/// Detailed fetch with a hard timeout (so UI doesn’t hang).
Future<OsrmRouteDetailed> fetchOsrmRouteDetailed({
  required LatLng start,
  required LatLng end,
  Duration timeout = const Duration(seconds: 6),
}) async {
  final base = getOsrmBaseUrl();
  final uri = Uri.parse(
    '$base/route/v1/driving/'
    '${start.longitude},${start.latitude};'
    '${end.longitude},${end.latitude}'
    '?overview=full&geometries=geojson',
  );

  final res = await http.get(uri).timeout(timeout);
  if (res.statusCode != 200) {
    throw Exception('OSRM error ${res.statusCode}: ${res.body}');
  }

  final body = json.decode(res.body) as Map<String, dynamic>;
  final routes = (body['routes'] as List?) ?? const [];
  if (routes.isEmpty) throw Exception('OSRM: no routes found');

  final r0 = routes.first as Map<String, dynamic>;
  final coords = ((r0['geometry'] as Map)['coordinates'] as List).cast<List>();
  final points =
      coords
          .map(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();

  final distance = (r0['distance'] as num?)?.toInt() ?? 0; // meters
  final duration = (r0['duration'] as num?)?.toInt() ?? 0; // seconds

  return OsrmRouteDetailed(
    points: points,
    distanceMeters: distance,
    durationSeconds: duration,
  );
}
