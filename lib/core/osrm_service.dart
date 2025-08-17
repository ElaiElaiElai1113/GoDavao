// lib/core/osrm_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Keep your existing simple polyline fetch for map previews
Future<Polyline> fetchOsrmRoute({
  required LatLng start,
  required LatLng end,
  Color color = Colors.blue,
  double width = 4,
}) async {
  final host =
      (defaultTargetPlatform == TargetPlatform.android)
          ? '10.0.2.2'
          : 'localhost';

  final uri = Uri.parse(
    'http://$host:5000/route/v1/driving/'
    '${start.longitude},${start.latitude};'
    '${end.longitude},${end.latitude}'
    '?overview=full&geometries=geojson',
  );

  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('OSRM error ${res.statusCode}: ${res.body}');
  }

  final body = json.decode(res.body) as Map<String, dynamic>;
  final routes = (body['routes'] as List?) ?? [];
  if (routes.isEmpty) throw Exception('OSRM: no routes found');

  final r0 = routes.first as Map<String, dynamic>;
  final coords = ((r0['geometry'] as Map)['coordinates'] as List).cast<List>();
  final points =
      coords
          .map(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();

  return Polyline(points: points, strokeWidth: width, color: color);
}

/// Detailed model for OSRM results
class OsrmRouteDetailed {
  final List<LatLng> points;
  final int distanceMeters; // routes[0].distance
  final int durationSeconds; // routes[0].duration

  OsrmRouteDetailed({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  Polyline toPolyline({Color color = Colors.blue, double width = 4}) {
    return Polyline(points: points, strokeWidth: width, color: color);
  }
}

/// Detailed fetch: polyline + distance + duration
Future<OsrmRouteDetailed> fetchOsrmRouteDetailed({
  required LatLng start,
  required LatLng end,
}) async {
  final host =
      (defaultTargetPlatform == TargetPlatform.android)
          ? '10.0.2.2'
          : 'localhost';

  final uri = Uri.parse(
    'http://$host:5000/route/v1/driving/'
    '${start.longitude},${start.latitude};'
    '${end.longitude},${end.latitude}'
    '?overview=full&geometries=geojson',
  );

  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('OSRM error ${res.statusCode}: ${res.body}');
  }

  final body = json.decode(res.body) as Map<String, dynamic>;
  final routes = (body['routes'] as List?) ?? [];
  if (routes.isEmpty) {
    throw Exception('OSRM: no routes found');
  }

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
