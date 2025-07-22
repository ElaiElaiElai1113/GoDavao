import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'driver_ride_status_page.dart';

// import the global plugin instance
import 'package:godavao/main.dart' show localNotify;

class PassengerRidesPage extends StatefulWidget {
  const PassengerRidesPage({super.key});

  @override
  _PassengerRidesPageState createState() => _PassengerRidesPageState();
}

class _PassengerRidesPageState extends State<PassengerRidesPage> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _rideChannel;

  List<Map<String, dynamic>> _rides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRides();
    _setupRealtimeSubscription();
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'rides_channel',
      'Ride Updates',
      channelDescription: 'Alerts when ride status changes',
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

  Future<void> _loadRides() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final data = await _supabase
          .from('ride_requests')
          .select('''
            id,
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng,
            status,
            created_at
          ''')
          .eq('passenger_id', user.id)
          .order('created_at', ascending: false);

      final raw =
          (data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      final enriched = await Future.wait(
        raw.map((ride) async {
          final pLat = ride['pickup_lat'] as double;
          final pLng = ride['pickup_lng'] as double;
          final dLat = ride['destination_lat'] as double;
          final dLng = ride['destination_lng'] as double;

          final pMarks = await placemarkFromCoordinates(pLat, pLng);
          final dMarks = await placemarkFromCoordinates(dLat, dLng);

          String fmt(Placemark m) => [
            m.thoroughfare,
            m.subLocality,
            m.locality,
          ].where((s) => s!.isNotEmpty).join(', ');

          return {
            ...ride,
            'pickup_address': fmt(pMarks.first),
            'destination_address': fmt(dMarks.first),
          };
        }),
      );

      setState(() => _rides = enriched);
    } catch (e) {
      debugPrint('Error loading or geocoding rides: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _setupRealtimeSubscription() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _rideChannel = _supabase.channel('ride_requests:${user.id}');
    _rideChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ride_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'passenger_id',
            value: user.id,
          ),
          callback: (payload) async {
            final updated = Map<String, dynamic>.from(payload.newRecord!);
            // reverse‑geocode:
            final pMarks = await placemarkFromCoordinates(
              updated['pickup_lat'] as double,
              updated['pickup_lng'] as double,
            );
            final dMarks = await placemarkFromCoordinates(
              updated['destination_lat'] as double,
              updated['destination_lng'] as double,
            );
            String fmt(Placemark m) => [
              m.thoroughfare,
              m.subLocality,
              m.locality,
            ].where((s) => s!.isNotEmpty).join(', ');
            updated['pickup_address'] = fmt(pMarks.first);
            updated['destination_address'] = fmt(dMarks.first);

            setState(() {
              _rides =
                  _rides
                      .map((r) => r['id'] == updated['id'] ? updated : r)
                      .toList();
            });

            // both snack bar & local notification:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ride status: ${updated['status']}')),
            );
            _showNotification(
              'Ride Update',
              'Your ride status is now ${updated['status']}',
            );
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_rideChannel != null) {
      _supabase.removeChannel(_rideChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Rides')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadRides,
                child: ListView.builder(
                  itemCount: _rides.length,
                  itemBuilder: (context, i) {
                    final ride = _rides[i];
                    return ListTile(
                      title: Text(
                        '${ride['pickup_address']}\n→ ${ride['destination_address']}',
                      ),
                      subtitle: Text('Status: ${ride['status']}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) =>
                                      DriverRideStatusPage(rideId: ride['id']),
                            ),
                          ),
                    );
                  },
                ),
              ),
    );
  }
}
