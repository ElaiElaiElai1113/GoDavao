import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:godavao/main.dart' show localNotify;

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
  double _distanceKm = 0;
  double _fare = 0;
  final Distance _dist = const Distance();

  @override
  void initState() {
    super.initState();
    _calculateFare();
  }

  void _calculateFare() {
    final meters = _dist(widget.pickup, widget.destination);
    final km = meters / 1000;
    final mins = km / 40 * 60;
    const base = 50.0, perKm = 10.0, perMin = 2.0;
    final fare = base + perKm * km + perMin * mins;
    setState(() {
      _distanceKm = km;
      _fare = fare;
      _loading = false;
    });
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
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in')));
      return setState(() => _loading = false);
    }

    try {
      // 1) create ride_request, stamping driver_route_id
      final req =
          await supabase
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
      final rideReqId = req?['id'] as String?;

      if (rideReqId == null) throw 'Failed to create ride request';

      // 2) create ride_match
      await supabase.from('ride_matches').insert({
        'ride_request_id': rideReqId,
        'driver_route_id': widget.routeId,
        'driver_id': widget.driverId,
        'status': 'pending',
      });

      _showNotification(
        'Ride Requested',
        'Your ride (₱${_fare.toStringAsFixed(2)}) has been requested',
      );

      Navigator.pushReplacementNamed(context, '/passenger_rides');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
      _showNotification('Request Failed', e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Your Ride')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: widget.pickup, zoom: 13),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.yourcompany.godavao',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [widget.pickup, widget.destination],
                      strokeWidth: 4,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
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
                Text('Distance: ${_distanceKm.toStringAsFixed(2)} km'),
                const SizedBox(height: 8),
                Text('Estimated Fare: ₱${_fare.toStringAsFixed(2)}'),
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
                                color: Colors.white,
                                strokeWidth: 2,
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
