// lib/features/maps/passenger_map_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// import your global notifications instance
import 'package:godavao/main.dart' show localNotify;

import '../ride/presentation/confirm_ride_page.dart';

class DriverRoute {
  final String id;
  final String driverId;
  final String polyline;
  DriverRoute.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      driverId = m['driver_id'] as String,
      polyline = m['route_polyline'] as String;
}

class PassengerMapPage extends StatefulWidget {
  const PassengerMapPage({super.key});
  @override
  State<PassengerMapPage> createState() => _PassengerMapPageState();
}

class _PassengerMapPageState extends State<PassengerMapPage> {
  final supabase = Supabase.instance.client;
  final polylinePoints = PolylinePoints();

  bool loading = true;
  String? errorMessage;

  List<DriverRoute> _routes = [];
  DriverRoute? _selectedRoute;
  List<LatLng> _routePoints = [];

  LatLng? _pickupLocation;
  String? _pickupAddress;

  LatLng? _dropoffLocation;
  String? _dropoffAddress;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final data = await supabase
          .from('driver_routes')
          .select('id, driver_id, route_polyline');
      _routes =
          (data as List)
              .map((m) => DriverRoute.fromMap(m as Map<String, dynamic>))
              .toList();

      if (_routes.isEmpty) throw Exception('No driver routes available');

      _selectRoute(_routes.first);
    } catch (e) {
      errorMessage = 'Failed to load routes: $e';
    } finally {
      setState(() => loading = false);
    }
  }

  void _selectRoute(DriverRoute r) {
    final pts = polylinePoints.decodePolyline(r.polyline);
    _routePoints = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
    setState(() {
      _selectedRoute = r;
      _pickupLocation = null;
      _pickupAddress = null;
      _dropoffLocation = null;
      _dropoffAddress = null;
    });
  }

  Future<String> _reverseGeocode(LatLng loc) async {
    try {
      final pm = await placemarkFromCoordinates(loc.latitude, loc.longitude);
      final p = pm.first;
      return '${p.street}, ${p.locality}';
    } catch (_) {
      return 'Unknown location';
    }
  }

  LatLng _snapToRoute(LatLng tap, List<LatLng> route) {
    final dist = Distance();
    LatLng best = route.first;
    double bestD = double.infinity;

    for (int i = 0; i < route.length - 1; i++) {
      final a = route[i], b = route[i + 1];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final len2 = dx * dx + dy * dy;
      if (len2 == 0) continue;
      final t =
          ((tap.longitude - a.longitude) * dx +
              (tap.latitude - a.latitude) * dy) /
          len2;
      final ct = t.clamp(0.0, 1.0);
      final proj = LatLng(a.latitude + ct * dy, a.longitude + ct * dx);
      final d = dist(proj, tap);
      if (d < bestD) {
        bestD = d;
        best = proj;
      }
    }
    return best;
  }

  void _onMapTap(TapPosition _, LatLng latlng) async {
    if (_routePoints.isEmpty) return;

    if (_pickupLocation == null) {
      final snapped = _snapToRoute(latlng, _routePoints);
      final addr = await _reverseGeocode(snapped);
      setState(() {
        _pickupLocation = snapped;
        _pickupAddress = addr;
      });
    } else if (_dropoffLocation == null) {
      final snapped = _snapToRoute(latlng, _routePoints);
      final addr = await _reverseGeocode(snapped);
      setState(() {
        _dropoffLocation = snapped;
        _dropoffAddress = addr;
      });
    } else {
      final snapped = _snapToRoute(latlng, _routePoints);
      final addr = await _reverseGeocode(snapped);
      setState(() {
        _pickupLocation = snapped;
        _pickupAddress = addr;
        _dropoffLocation = null;
        _dropoffAddress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Join a Driver Route')),
        body: Center(child: Text(errorMessage!)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Join a Driver Route')),
      body: Column(
        children: [
          // Route selector
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _routes.length,
              itemBuilder: (_, i) {
                final r = _routes[i];
                final sel = r.id == _selectedRoute?.id;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: sel ? Colors.blue : Colors.grey.shade200,
                    ),
                    onPressed: () => _selectRoute(r),
                    child: Text(
                      'Route ${i + 1}',
                      style: TextStyle(
                        color: sel ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Map
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                center:
                    _routePoints.isNotEmpty
                        ? _routePoints.first
                        : LatLng(7.1907, 125.4553),
                zoom: 13,
                onTap: _onMapTap,
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
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                if (_pickupLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickupLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                if (_dropoffLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _dropoffLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Confirm button with local notification
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed:
                  _pickupLocation == null
                      ? null
                      : () async {
                        // Fire local notification
                        final destText = _dropoffAddress ?? 'end of the route';
                        await localNotify.show(
                          0,
                          'Ride Requested',
                          'Pickup at ${_pickupAddress ?? 'route'} → $destText',
                          const NotificationDetails(
                            android: AndroidNotificationDetails(
                              'rides_channel',
                              'Ride Updates',
                              channelDescription:
                                  'Alerts when you confirm a ride',
                              importance: Importance.max,
                              priority: Priority.high,
                            ),
                            iOS: DarwinNotificationDetails(),
                          ),
                        );

                        // Navigate to confirmation
                        final pickup = _pickupLocation!;
                        final destination =
                            _dropoffLocation ?? _routePoints.last;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => ConfirmRidePage(
                                  pickup: pickup,
                                  destination: destination,
                                  routeId: _selectedRoute!.id,
                                  driverId: _selectedRoute!.driverId,
                                ),
                          ),
                        );
                      },
              child: const Text('Request Ride'),
            ),
          ),
        ],
      ),
    );
  }
}
