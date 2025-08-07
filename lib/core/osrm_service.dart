import 'dart:convert';
import 'package:godavao/main.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

/// Swap these imports if you use google_maps_flutter instead:
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Fetches an OSRM‐computed route and returns it as a Polyline.
Future<Polyline> fetchOsrmRoute({
  required LatLng start,
  required LatLng end,
  Color color = Colors.blue,
  double width = 4,
}) async {
  // On Android emulator use 10.0.2.2; on iOS or desktop use localhost
  final host =
      Theme.of(navigatorKey.currentContext!).platform == TargetPlatform.android
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
    throw Exception('OSRM error ${res.statusCode}');
  }
  final body = json.decode(res.body) as Map<String, dynamic>;
  final coords =
      (body['routes'][0]['geometry']['coordinates'] as List)
          .cast<List<dynamic>>();

  final points =
      coords
          .map(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();

  return Polyline(points: points, strokeWidth: width, color: color);
}
