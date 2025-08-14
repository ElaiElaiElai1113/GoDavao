import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:godavao/main.dart' show localNotify;

// ⬇️ Ratings imports
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, super.key});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  Map<String, dynamic>? _ride;
  bool _loading = true;
  String? _error;

  bool _ratingPromptShown = false;

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
    if (!mounted) return;
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
            passenger_id
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (r == null) throw Exception('Ride not found');
      _ride = Map<String, dynamic>.from(r as Map);

      await _maybePromptRatingIfCompleted();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!mounted) return;
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
              callback: (payload) async {
                final updated = Map<String, dynamic>.from(payload.newRecord);
                if (!mounted) return;

                setState(() => _ride = updated);
                await _showNotification(
                  'Ride Update',
                  'Passenger status is now ${updated['status']}',
                );

                await _maybePromptRatingIfCompleted();
              },
            )
            .subscribe();
  }

  Future<void> _maybePromptRatingIfCompleted() async {
    if (_ratingPromptShown) return;
    final status = _ride?['status']?.toString();
    if (status != 'completed') return;

    final uid = supabase.auth.currentUser?.id;
    final passengerId = _ride?['passenger_id']?.toString();
    if (uid == null || passengerId == null) return;

    final existing = await RatingsService(supabase).getExistingRating(
      rideId: widget.rideId,
      raterUserId: uid,
      rateeUserId: passengerId,
    );
    if (existing != null) return;

    if (!mounted) return;
    _ratingPromptShown = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => RateUserSheet(
            rideId: widget.rideId,
            raterUserId: uid,
            rateeUserId: passengerId,
            rateeName: 'Passenger',
            rateeRole: 'passenger',
          ),
    );
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (_ride == null) {
      return const Scaffold(body: Center(child: Text('No ride data')));
    }

    final r = _ride!;
    final pickup = LatLng(r['pickup_lat'], r['pickup_lng']);
    final dest = LatLng(r['destination_lat'], r['destination_lng']);

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Ride Details')),
      body: Column(
        children: [
          // Passenger row with badge
          ListTile(
            title: Row(
              children: [
                Expanded(child: Text('Passenger: ${r['passenger_id']}')),
                if (r['passenger_id'] != null)
                  UserRatingBadge(
                    userId: r['passenger_id'].toString(),
                    iconSize: 14,
                  ),
              ],
            ),
            subtitle: Text('Status: ${r['status']}'),
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
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                    Marker(
                      point: dest,
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

          // Rating action button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                if (r['status'] == 'completed' && r['passenger_id'] != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.star),
                      label: const Text('Rate your passenger'),
                      onPressed: () async {
                        _ratingPromptShown = false;
                        await _maybePromptRatingIfCompleted();
                      },
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
