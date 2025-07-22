import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// import the global plugin instance
import 'package:godavao/main.dart' show localNotify;

class DriverRoutePage extends StatefulWidget {
  const DriverRoutePage({super.key});

  @override
  State<DriverRoutePage> createState() => _DriverRoutePageState();
}

class _DriverRoutePageState extends State<DriverRoutePage> {
  final MapController _mapController = MapController();
  final List<LatLng> _routePoints = [];
  bool _publishing = false;

  void _onMapLongPress(TapPosition _, LatLng latlng) {
    setState(() => _routePoints.add(latlng));
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'routes_channel',
      'Route Alerts',
      channelDescription: 'Notifications for route publishing',
      importance: Importance.max,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await localNotify.show(
      0,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
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
      final coords =
          _routePoints.map((p) => [p.latitude, p.longitude]).toList();
      final encodedPolyline = gpa.encodePolyline(coords);

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      await Supabase.instance.client.from('driver_routes').insert({
        'driver_id': user.id,
        'route_polyline': encodedPolyline,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route published successfully!')),
      );
      _showNotification(
        'Route Published',
        'Your driver route has been published.',
      );

      setState(() => _routePoints.clear());
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to publish route: $e')));
      _showNotification('Publish Failed', 'Could not publish route: $e');
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
              center: LatLng(7.1907, 125.4553),
              zoom: 13,
              onLongPress: _onMapLongPress,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yourcompany.godavao',
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
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
