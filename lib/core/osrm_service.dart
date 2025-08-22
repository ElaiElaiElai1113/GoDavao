// lib/core/osrm_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 👉 Set this if you host your own OSRM (prefer HTTPS in production).
/// Leave null to use the public OSRM server (good for pilots).
const String? kOsrmOverrideBaseUrl = null; // e.g. 'https://osrm.example.com'

/// Public OSRM works on real devices. If you set an http:// URL for dev,
/// remember to add android:usesCleartextTraffic="true" in AndroidManifest.
String getOsrmBaseUrl() =>
    kOsrmOverrideBaseUrl ?? 'https://router.project-osrm.org';

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

/// Simple preview polyline (kept for compatibility).
/// Never throws; returns a straight-line polyline if OSRM fails.
Future<Polyline> fetchOsrmRoute({
  required LatLng start,
  required LatLng end,
  Color color = Colors.blue,
  double width = 4,
}) async {
  final d = await fetchOsrmRouteDetailed(start: start, end: end);
  return d.toPolyline(color: color, width: width);
}

/// Detailed fetch with timeout + retry.
/// Never throws; returns a straight-line fallback on any failure.
Future<OsrmRouteDetailed> fetchOsrmRouteDetailed({
  required LatLng start,
  required LatLng end,
  Duration timeout = const Duration(seconds: 8),
}) async {
  Future<OsrmRouteDetailed?> _tryOnce({required String overview}) async {
    final base = getOsrmBaseUrl();
    // OSRM requires lon,lat order in the URL
    final uri = Uri.parse(
      '$base/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=$overview&geometries=geojson&alternatives=false&steps=false',
    );
    if (kDebugMode) debugPrint('[OSRM] GET $uri');

    final res = await http.get(uri).timeout(timeout);
    if (res.statusCode != 200) return null;

    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['code'] != 'Ok') return null;

    final routes = (body['routes'] as List?) ?? const [];
    if (routes.isEmpty) return null;

    final r0 = routes.first as Map<String, dynamic>;
    final geom = (r0['geometry'] as Map<String, dynamic>?) ?? const {};
    final coords = (geom['coordinates'] as List?)?.cast<List>();
    if (coords == null || coords.isEmpty) return null;

    final pts =
        coords
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();

    final distance = (r0['distance'] as num?)?.toInt() ?? 0; // meters
    final duration = (r0['duration'] as num?)?.toInt() ?? 0; // seconds

    return OsrmRouteDetailed(
      points: pts,
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }

  try {
    // Smaller, faster payload first
    final a = await _tryOnce(overview: 'simplified');
    if (a != null) return a;

    // Brief backoff then try full once
    await Future.delayed(const Duration(milliseconds: 300));
    final b = await _tryOnce(overview: 'full');
    if (b != null) return b;
  } catch (_) {
    // swallow – we’ll return a fallback below
  }

  // Fallback: straight line between start and end (never throws)
  return _straightLineFallback(start: start, end: end);
}

/// Builds a safe straight-line fallback with basic distance estimate.
/// Duration left as 0 (or you can estimate with an average city speed).
OsrmRouteDetailed _straightLineFallback({
  required LatLng start,
  required LatLng end,
}) {
  // Haversine distance in meters
  final d = const Distance().as(LengthUnit.Meter, start, end).round();
  return OsrmRouteDetailed(
    points: <LatLng>[start, end],
    distanceMeters: d,
    durationSeconds: 0,
  );
}
