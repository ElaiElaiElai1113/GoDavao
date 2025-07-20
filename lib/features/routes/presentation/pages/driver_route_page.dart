import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverRoutePage extends StatefulWidget {
  const DriverRoutePage({Key? key}) : super(key: key);

  @override
  State<DriverRoutePage> createState() => _DriverRoutePageState();
}

class _DriverRoutePageState extends State<DriverRoutePage> {
  final MapController _mapController = MapController();
  final PolylinePoints _polylinePoints = PolylinePoints();
  final List<LatLng> _routePoints = [];
  bool _publishing = false;

  /// Add a point to the route when the driver long‑presses the map.
  void _onMapLongPress(TapPosition _, LatLng latlng) {
    setState(() {
      _routePoints.add(latlng);
    });
  }

  Future<void> _publishRoute() async {
    if (_routePoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw at least two points first.')),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      // Convert LatLng list → List<List<double>> for encoding
      final coords =
          _routePoints.map((p) => [p.latitude, p.longitude]).toList();

      // Encode to polyline string
      final String encodedPolyline = gpa.encodePolyline(coords);

      // Insert into Supabase
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Not signed in');
      }

      await Supabase.instance.client.from('driver_routes').insert({
        'driver_id': user.id,
        'route_polyline': encodedPolyline,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route published successfully!')),
      );

      // Optionally clear the drawn points:
      setState(() => _routePoints.clear());
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to publish route: $e')));
    } finally {
      setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draw & Publish Driver Route')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(7.1907, 125.4553), // Davao center
              zoom: 13,
              onLongPress: _onMapLongPress,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.godavao',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(
                markers:
                    _routePoints
                        .map(
                          (p) => Marker(
                            point: p,
                            width: 30,
                            height: 30,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),

          // Publish button at bottom
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.publish),
              label:
                  _publishing
                      ? const Text('Publishing…')
                      : const Text('Publish Route'),
              onPressed: _publishing ? null : _publishRoute,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
