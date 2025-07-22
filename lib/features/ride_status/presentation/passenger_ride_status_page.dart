// lib/features/ride_status/presentation/passenger_ride_status_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// import your global instance:
import 'package:godavao/main.dart' show localNotify;

class PassengerRideStatusPage extends StatefulWidget {
  final String rideId;
  const PassengerRideStatusPage({required this.rideId, Key? key})
    : super(key: key);

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  Map<String, dynamic>? _ride;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRide();
    _subscribeToUpdates();
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'rides_channel',
      'Ride Updates',
      channelDescription: 'Notifications for ride status changes',
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

  Future<void> _loadRide() async {
    setState(() => _loading = true);
    try {
      final r =
          await supabase
              .from('ride_requests')
              .select('''
            id,
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng,
            status,
            driver_route_id
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (r == null) throw Exception('Ride not found');
      setState(() => _ride = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _subscribeToUpdates() {
    _channel =
        supabase
            .channel('ride_requests_${widget.rideId}')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_requests',
              event: PostgresChangeEvent.update,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: widget.rideId,
              ),
              callback: (payload) {
                final updated = payload.newRecord! as Map<String, dynamic>;
                setState(() => _ride = updated);
                _showNotification(
                  'Ride Update',
                  'Your ride is now ${updated['status']}',
                );
              },
            )
            .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null)
      return Scaffold(body: Center(child: Text('Error: $_error')));
    if (_ride == null)
      return const Scaffold(body: Center(child: Text('No ride data')));

    final r = _ride!;
    final pickup = LatLng(r['pickup_lat'], r['pickup_lng']);
    final dest = LatLng(r['destination_lat'], r['destination_lng']);

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Details')),
      body: Column(
        children: [
          ListTile(
            title: Text('Status: ${r['status']}'),
            subtitle: Text(
              'Driver route: ${r['driver_route_id'] ?? 'unassigned'}',
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: pickup, zoom: 13),
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
                      points: [pickup, dest],
                      strokeWidth: 4,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.green,
                      ),
                    ),
                    Marker(
                      point: dest,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
