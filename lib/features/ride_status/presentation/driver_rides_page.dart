// lib/features/ride_status/presentation/driver_rides_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// import the global instance:
import 'package:godavao/main.dart' show localNotify;

import 'driver_ride_status_page.dart';

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({Key? key}) : super(key: key);

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage> {
  final supabase = Supabase.instance.client;
  final _poly = PolylinePoints();

  List<Map<String, dynamic>> _ongoing = [];
  List<Map<String, dynamic>> _completed = [];
  bool _loading = true;
  RealtimeChannel? _matchChannel;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'matches_channel',
      'Match Alerts',
      channelDescription: 'New ride matches',
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

  Future<void> _loadMatches() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    // 1) fetch latest driver_route
    final routeData =
        await supabase
            .from('driver_routes')
            .select('id, route_polyline')
            .eq('driver_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (routeData == null) {
      _ongoing = [];
      _completed = [];
      setState(() => _loading = false);
      return;
    }

    final routeId = routeData['id'] as String;

    // set up realtime if not already
    _subscribeToNewMatches(routeId);

    final pts =
        _poly
            .decodePolyline(routeData['route_polyline'] as String)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

    // 2) fetch existing matches
    final raw = await supabase
        .from('ride_matches')
        .select(r'''
          id,
          ride_request_id,
          status,
          created_at,
          ride_requests!ride_matches_ride_request_id_fkey (
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng,
            users!ride_requests_passenger_id_fkey (
              name
            )
          )
        ''')
        .eq('driver_route_id', routeId)
        .order('created_at', ascending: true);

    // 3) enrich & sort
    final dist = Distance();
    final enriched = <Map<String, dynamic>>[];
    for (var m in raw as List) {
      final rideReq = m['ride_requests'] as Map<String, dynamic>?;
      if (rideReq == null) continue;
      final passenger =
          ((rideReq['users'] ?? {}) as Map)['name'] as String? ?? 'Unknown';
      final lat = (rideReq['pickup_lat'] as num?)?.toDouble();
      final lng = (rideReq['pickup_lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final pickPt = LatLng(lat, lng);

      int bestI = 0;
      double bestD = double.infinity;
      for (int i = 0; i < pts.length; i++) {
        final d = dist(pts[i], pickPt);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }

      enriched.add({
        'match_id': m['id'] as String,
        'ride_request_id': m['ride_request_id'] as String,
        'status': m['status'] as String,
        'created_at': m['created_at'] as String,
        'passenger': passenger,
        'pickup_point': pickPt,
        'route_index': bestI,
      });
    }

    enriched.sort((a, b) => a['route_index'].compareTo(b['route_index']));
    _ongoing = enriched.where((e) => e['status'] != 'completed').toList();
    _completed = enriched.where((e) => e['status'] == 'completed').toList();

    setState(() => _loading = false);
  }

  void _subscribeToNewMatches(String routeId) {
    if (_matchChannel != null) return;

    _matchChannel =
        supabase
            .channel('ride_matches_route_$routeId')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_matches',
              event: PostgresChangeEvent.insert,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'driver_route_id',
                value: routeId,
              ),
              callback: (payload) {
                final m = payload.newRecord! as Map<String, dynamic>;
                final passenger =
                    (m['ride_requests']?['users']?['name']) as String? ??
                    'a passenger';
                _showNotification(
                  'New Request',
                  'Pickup request from $passenger',
                );
                _loadMatches();
              },
            )
            .subscribe();
  }

  @override
  void dispose() {
    if (_matchChannel != null) supabase.removeChannel(_matchChannel!);
    super.dispose();
  }

  Future<void> _updateMatchStatus(
    String matchId,
    String rideRequestId,
    String newStatus,
  ) async {
    setState(() => _loading = true);

    try {
      await supabase
          .from('ride_matches')
          .update({'status': newStatus})
          .eq('id', matchId);

      final updateData = {'status': newStatus};
      if (newStatus == 'accepted') {
        final user = supabase.auth.currentUser!;
        final rd =
            await supabase
                .from('driver_routes')
                .select('id')
                .eq('driver_id', user.id)
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
        final rid = (rd as Map?)?['id'] as String?;
        if (rid != null) updateData['driver_route_id'] = rid;
      }

      await supabase
          .from('ride_requests')
          .update(updateData)
          .eq('id', rideRequestId);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ride $newStatus')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
    } finally {
      await _loadMatches();
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return Colors.grey;
      case 'accepted':
        return Colors.blue;
      case 'en_route':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'declined':
        return Colors.red;
      default:
        return Colors.black;
    }
  }

  Widget _card(Map<String, dynamic> m) {
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(m['created_at'] as String));
    final status = m['status'] as String;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Passenger: ${m['passenger']}',
              style: const TextStyle(fontSize: 16),
            ),
            Text('Requested: $dt'),
            Text(
              'Status: ${status.toUpperCase()}',
              style: TextStyle(color: _statusColor(status)),
            ),
            const SizedBox(height: 8),
            if (status == 'pending')
              Row(
                children: [
                  ElevatedButton(
                    onPressed:
                        () => _updateMatchStatus(
                          m['match_id'] as String,
                          m['ride_request_id'] as String,
                          'accepted',
                        ),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        () => _updateMatchStatus(
                          m['match_id'] as String,
                          m['ride_request_id'] as String,
                          'declined',
                        ),
                    child: const Text('Decline'),
                  ),
                ],
              )
            else if (status == 'accepted')
              ElevatedButton(
                onPressed:
                    () => _updateMatchStatus(
                      m['match_id'] as String,
                      m['ride_request_id'] as String,
                      'en_route',
                    ),
                child: const Text('Start Ride'),
              )
            else if (status == 'en_route')
              ElevatedButton(
                onPressed:
                    () => _updateMatchStatus(
                      m['match_id'] as String,
                      m['ride_request_id'] as String,
                      'completed',
                    ),
                child: const Text('Complete Ride'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Matches')),
      body: RefreshIndicator(
        onRefresh: _loadMatches,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Upcoming Pickups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._ongoing.map(_card),
            const Divider(),
            const Text(
              'Completed Pickups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._completed.map(_card),
          ],
        ),
      ),
    );
  }
}
