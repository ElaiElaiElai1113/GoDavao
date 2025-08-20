import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/features/rides/presentation/confirm_ride_page.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Decode Google-style encoded polylines
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import 'package:godavao/main.dart' show localNotify;

// OSRM service for fetching real routes
import 'package:godavao/core/osrm_service.dart';

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
  final _polyDecoder = PolylinePoints();

  bool _loadingRoutes = true;
  String? _routesError;

  List<DriverRoute> _routes = [];
  DriverRoute? _selectedRoute;
  List<LatLng> _routePoints = [];

  // OSRM-computed segment for passenger
  Polyline? _osrmRoute;

  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loadingRoutes = true;
      _routesError = null;
    });
    try {
      final data = await supabase
          .from('driver_routes')
          .select('id, driver_id, route_polyline');
      _routes =
          (data as List)
              .map((m) => DriverRoute.fromMap(m as Map<String, dynamic>))
              .toList();
      if (_routes.isEmpty) throw 'No routes available';
      _selectRoute(_routes.first);
    } catch (e) {
      _routesError = 'Error loading routes: $e';
    } finally {
      setState(() => _loadingRoutes = false);
    }
  }

  void _selectRoute(DriverRoute r) {
    final pts = _polyDecoder.decodePolyline(r.polyline);
    _routePoints =
        pts
            .map((p) => LatLng(p.latitude.toDouble(), p.longitude.toDouble()))
            .toList();
    setState(() {
      _selectedRoute = r;
      _pickupLocation = null;
      _dropoffLocation = null;
      _osrmRoute = null;
    });
  }

  void _onMapTap(TapPosition _, LatLng tap) async {
    if (_routePoints.isEmpty) return;

    // snap tap to nearest segment:
    late LatLng snapped;
    double bestD = double.infinity;
    final dist = Distance();
    for (var i = 0; i < _routePoints.length - 1; i++) {
      final a = _routePoints[i], b = _routePoints[i + 1];
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
        snapped = proj;
      }
    }

    if (_pickupLocation == null) {
      setState(() => _pickupLocation = snapped);
    } else if (_dropoffLocation == null) {
      setState(() {
        _dropoffLocation = snapped;
        _osrmRoute = null;
      });
      // fetch OSRM segment
      try {
        final fetched = await fetchOsrmRoute(
          start: _pickupLocation!,
          end: _dropoffLocation!,
        );
        setState(() => _osrmRoute = fetched);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Routing failed: $e')));
      }
    } else {
      // reset for new selection
      setState(() {
        _pickupLocation = snapped;
        _dropoffLocation = null;
        _osrmRoute = null;
      });
    }
  }

  Future<void> _onRequestRide() async {
    if (_pickupLocation == null || _dropoffLocation == null || _sending) return;

    if (_selectedRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a driver route first')),
      );
      return;
    }

    // No DB writes here. Just go to the confirm screen.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ConfirmRidePage(
              pickup: _pickupLocation!,
              destination: _dropoffLocation!,
              routeId: _selectedRoute!.id,
              driverId: _selectedRoute!.driverId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRoutes) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_routesError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Join a Driver Route')),
        body: Center(child: Text(_routesError!)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Join a Driver Route')),
      body: Column(
        children: [
          // Route selector
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children:
                  _routes.map((r) {
                    final sel = r.id == _selectedRoute?.id;
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              sel ? Colors.blue : Colors.grey.shade200,
                        ),
                        onPressed: () => _selectRoute(r),
                        child: Text(sel ? 'Selected' : 'Route'),
                      ),
                    );
                  }).toList(),
            ),
          ),

          // Map + polylines/markers
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
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4,
                        color: Colors.red,
                      ),
                    ],
                  ),
                if (_osrmRoute != null) PolylineLayer(polylines: [_osrmRoute!]),
                if (_pickupLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickupLocation!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                if (_dropoffLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _dropoffLocation!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Request Ride button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed:
                  (_pickupLocation != null &&
                          _dropoffLocation != null &&
                          !_sending)
                      ? _onRequestRide
                      : null,
              child:
                  _sending
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('Review Fare'),
            ),
          ),
        ],
      ),
    );
  }
}
