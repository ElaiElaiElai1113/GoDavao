import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/features/rides/presentation/fare_breakdown_row.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/main.dart' show localNotify;

// NEW
import 'package:godavao/features/rides/data/fare_calculator.dart';

class ConfirmRidePage extends StatefulWidget {
  final LatLng pickup;
  final LatLng destination;
  final String routeId;
  final String driverId;

  const ConfirmRidePage({
    required this.pickup,
    required this.destination,
    required this.routeId,
    required this.driverId,
    super.key,
  });

  @override
  State<ConfirmRidePage> createState() => _ConfirmRidePageState();
}

class _ConfirmRidePageState extends State<ConfirmRidePage> {
  bool _loading = true;
  String? _error;

  Polyline? _routePolyline;
  double _distanceKm = 0;
  double _durationMin = 0;
  double _fare = 0;

  FareBreakdown? _breakdown; // NEW

  @override
  void initState() {
    super.initState();
    _loadRouteAndFare();
  }

  double _deg2rad(double d) => d * pi / 180.0;
  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  Future<void> _loadRouteAndFare() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final d = await fetchOsrmRouteDetailed(
        start: widget.pickup,
        end: widget.destination,
        timeout: const Duration(seconds: 6),
      );

      final km = d.distanceMeters / 1000.0;
      final mins = max(d.durationSeconds / 60.0, 1.0);

      final breakdown = FareCalculator.estimate(km: km, minutes: mins);

      if (!mounted) return;
      setState(() {
        _routePolyline = d.toPolyline(color: Colors.blue, width: 4);
        _distanceKm = breakdown.km;
        _durationMin = breakdown.minutes;
        _fare = breakdown.total;
        _breakdown = breakdown;
        _loading = false;
      });
    } catch (_) {
      // Fallback straight line when OSRM is unavailable
      final km = _haversineKm(widget.pickup, widget.destination);
      const avgKmh = 22.0;
      final mins = max((km / avgKmh) * 60.0, 1.0);
      final breakdown = FareCalculator.estimate(km: km, minutes: mins);

      if (!mounted) return;
      setState(() {
        _routePolyline = Polyline(
          points: [widget.pickup, widget.destination],
          strokeWidth: 4,
          color: Colors.blue,
        );
        _distanceKm = breakdown.km;
        _durationMin = breakdown.minutes;
        _fare = breakdown.total;
        _breakdown = breakdown;
        _error = 'OSRM unavailable — using approximate route.';
        _loading = false;
      });
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'rides_channel',
      'Ride Updates',
      channelDescription: 'Alerts when you confirm a ride',
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

  Future<void> _confirmRide() async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not logged in')));
      }
      setState(() => _loading = false);
      return;
    }

    try {
      // 1) Create the ride request
      final req =
          await sb
              .from('ride_requests')
              .insert({
                'passenger_id': user.id,
                'pickup_lat': widget.pickup.latitude,
                'pickup_lng': widget.pickup.longitude,
                'destination_lat': widget.destination.latitude,
                'destination_lng': widget.destination.longitude,
                'fare': _fare,
                'driver_route_id': widget.routeId,
                'status': 'pending',
              })
              .select('id')
              .maybeSingle();

      final rideReqId = (req)?['id'] as String?;
      if (rideReqId == null) throw 'Failed to create ride request';

      // 2) Create the match (still pending for driver to accept)
      await sb.from('ride_matches').insert({
        'ride_request_id': rideReqId,
        'driver_route_id': widget.routeId,
        'driver_id': widget.driverId,
        'status': 'pending',
      });

      // 3) Optional: belt & suspenders — insert an on_hold payment record
      // (If you already have a DB trigger that makes this, let this be best-effort.)
      await sb
          .from('payments')
          .insert({
            'ride_id': rideReqId,
            'amount': _fare,
            'method': 'gcash',
            'status': 'on_hold',
          })
          .onError((_, __) => {}); // ignore unique conflict if trigger ran

      await _showNotification(
        'Ride Requested',
        'Your ride (₱${_fare.toStringAsFixed(2)}) has been requested.',
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/passenger_rides');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      await _showNotification('Request Failed', e.toString());
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (widget.pickup.latitude + widget.destination.latitude) / 2,
      (widget.pickup.longitude + widget.destination.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Your Ride')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: center, zoom: 13),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (_routePolyline != null)
                  PolylineLayer(polylines: [_routePolyline!]),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                    Marker(
                      point: widget.destination,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.orange.shade700),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Distance: ${_distanceKm.toStringAsFixed(2)} km'),
                    Text('Time: ${_durationMin.toStringAsFixed(0)} min'),
                  ],
                ),
                const SizedBox(height: 12),

                // NEW: show the full fare breakdown
                if (_breakdown != null)
                  FareBreakdownRow(breakdown: _breakdown!),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _confirmRide,
                    child:
                        _loading
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              'Confirm & Pay ₱${_fare.toStringAsFixed(2)}',
                            ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
