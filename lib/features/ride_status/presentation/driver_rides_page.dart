// lib/features/ride_status/presentation/driver_rides_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// global notifications instance
import 'package:godavao/main.dart' show localNotify;

import 'driver_ride_status_page.dart';

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({Key? key}) : super(key: key);

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _poly = PolylinePoints();
  final _dist = Distance();

  List<LatLng> _routePoints = []; // decoded driver route
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _declined = [];
  List<Map<String, dynamic>> _completed = [];
  Set<String> _newMatchIds = {};

  bool _loading = true;
  RealtimeChannel? _matchChannel;
  late TabController _tabController;
  final _listScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMatches();
  }

  void _showRideSheet(Map<String, dynamic> ride) {
    final id = ride['match_id'] as String;
    final status = (ride['status'] as String).toLowerCase();
    final pickup = ride['pickup_address'] as String;
    final dropoff = ride['destination_address'] as String;
    final passenger = ride['passenger'] as String;
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(ride['created_at'] as String));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '$pickup → $dropoff',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Passenger: $passenger'),
              Text('Requested: $dt'),
              const SizedBox(height: 12),
              Text(
                'Status: ${status.toUpperCase()}',
                style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (status == 'pending') ...[
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateMatchStatus(
                          id,
                          ride['ride_request_id'],
                          'accepted',
                        );
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade200,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _updateMatchStatus(
                          id,
                          ride['ride_request_id'],
                          'declined',
                        );
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('Decline'),
                    ),
                  ] else if (status == 'accepted') ...[
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateMatchStatus(
                          id,
                          ride['ride_request_id'],
                          'en_route',
                        );
                      },
                      icon: const Icon(Icons.drive_eta),
                      label: const Text('Start Ride'),
                    ),
                  ] else if (status == 'en_route') ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _updateMatchStatus(
                          id,
                          ride['ride_request_id'],
                          'completed',
                        );
                      },
                      icon: const Icon(Icons.flag),
                      label: const Text('Complete Ride'),
                    ),
                  ] else ...[
                    Center(child: Text('No actions available')),
                  ],
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
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
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _loading = true);

    // 1) fetch & decode driver route
    final routeData =
        await _supabase
            .from('driver_routes')
            .select('id, route_polyline')
            .eq('driver_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (routeData == null) {
      setState(() {
        _upcoming = _declined = _completed = [];
        _routePoints = [];
        _loading = false;
      });
      return;
    }

    final pts =
        _poly
            .decodePolyline(routeData['route_polyline'] as String)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
    _routePoints = pts;

    _subscribeToNewMatches(routeData['id'] as String);

    // 2) fetch all ride_matches + nested ride_requests + passenger name
    final raw = await _supabase
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
            users!ride_requests_passenger_id_fkey ( name )
          )
        ''')
        .eq('driver_route_id', routeData['id'] as String)
        .order('created_at', ascending: true);

    // 3) enrich + split into upcoming/declined/completed
    final all = <Map<String, dynamic>>[];
    for (final m in raw as List) {
      final req = m['ride_requests'] as Map<String, dynamic>?;
      if (req == null) continue;

      final passenger = (req['users'] as Map?)?['name'] as String? ?? 'Unknown';
      final pLat = (req['pickup_lat'] as num).toDouble();
      final pLng = (req['pickup_lng'] as num).toDouble();
      final dLat = (req['destination_lat'] as num).toDouble();
      final dLng = (req['destination_lng'] as num).toDouble();

      // format addresses
      String fmt(Placemark pm) => [
        pm.thoroughfare,
        pm.subLocality,
        pm.locality,
      ].where((s) => s != null && s.isNotEmpty).cast<String>().join(', ');
      final pMark = (await placemarkFromCoordinates(pLat, pLng)).first;
      final dMark = (await placemarkFromCoordinates(dLat, dLng)).first;

      // find nearest point index
      int bestI = 0;
      double bestD = double.infinity;
      final pickPt = LatLng(pLat, pLng);
      for (var i = 0; i < pts.length; i++) {
        final d = _dist(pts[i], pickPt);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }

      all.add({
        'match_id': m['id'],
        'ride_request_id': m['ride_request_id'],
        'status': m['status'],
        'created_at': m['created_at'],
        'passenger': passenger,
        'pickup_point': pickPt,
        'pickup_address': fmt(pMark),
        'destination_address': fmt(dMark),
        'route_index': bestI,
      });
    }

    all.sort((a, b) => a['route_index'].compareTo(b['route_index']));

    setState(() {
      _upcoming =
          all
              .where(
                (e) => e['status'] != 'declined' && e['status'] != 'completed',
              )
              .toList();
      _declined = all.where((e) => e['status'] == 'declined').toList();
      _completed = all.where((e) => e['status'] == 'completed').toList();
      _loading = false;
    });
  }

  void _subscribeToNewMatches(String routeId) {
    if (_matchChannel != null) return;
    _matchChannel =
        _supabase
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
                final id = m['id'] as String;
                setState(() => _newMatchIds.add(id));
                _showNotification(
                  'New Request',
                  'Pickup request from ${(m['ride_requests']?['users']?['name']) ?? 'passenger'}',
                );
                _loadMatches();
              },
            )
            .subscribe();
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

  Widget _buildCard(Map<String, dynamic> m) {
    final id = m['match_id'] as String;
    final status = (m['status'] as String).toLowerCase();
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(m['created_at'] as String));

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.horizontal,
      // red “decline” background
      background: Container(
        color: Colors.red.shade100,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.close, color: Colors.red),
      ),
      // green “accept” background
      secondaryBackground: Container(
        color: Colors.green.shade100,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.check, color: Colors.green),
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          // swiped right → decline
          _updateMatchStatus(id, m['ride_request_id'], 'declined');
        } else {
          // swiped left → accept
          _updateMatchStatus(id, m['ride_request_id'], 'accepted');
        }
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showRideSheet(m),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${m['pickup_address']} → ${m['destination_address']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_newMatchIds.remove(id))
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Passenger: ${m['passenger']}'),
                Text('Requested: $dt'),
                const SizedBox(height: 8),
                Text(
                  'Status: ${status.toUpperCase()}',
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (status == 'pending')
                      ElevatedButton(
                        onPressed:
                            () => _updateMatchStatus(
                              id,
                              m['ride_request_id'],
                              'accepted',
                            ),
                        child: const Text('Accept'),
                      ),
                    if (status == 'pending') const SizedBox(width: 8),
                    if (status == 'pending')
                      TextButton(
                        onPressed:
                            () => _updateMatchStatus(
                              id,
                              m['ride_request_id'],
                              'declined',
                            ),
                        child: const Text('Decline'),
                      ),
                    if (status == 'accepted')
                      ElevatedButton(
                        onPressed:
                            () => _updateMatchStatus(
                              id,
                              m['ride_request_id'],
                              'en_route',
                            ),
                        child: const Text('Start Ride'),
                      ),
                    if (status == 'en_route')
                      ElevatedButton(
                        onPressed:
                            () => _updateMatchStatus(
                              id,
                              m['ride_request_id'],
                              'completed',
                            ),
                        child: const Text('Complete Ride'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateMatchStatus(
    String matchId,
    String rideRequestId,
    String newStatus,
  ) async {
    setState(() => _loading = true);
    await _supabase
        .from('ride_matches')
        .update({'status': newStatus})
        .eq('id', matchId);

    final upd = {'status': newStatus};
    if (newStatus == 'accepted') {
      final u = _supabase.auth.currentUser!;
      final rd =
          await _supabase
              .from('driver_routes')
              .select('id')
              .eq('driver_id', u.id)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
      final rid = (rd as Map?)?['id'] as String?;
      if (rid != null) upd['driver_route_id'] = rid;
    }
    await _supabase.from('ride_requests').update(upd).eq('id', rideRequestId);

    // inline move
    setState(() {
      final src = _upcoming;
      final item = src.firstWhere((e) => e['match_id'] == matchId);
      src.remove(item);
      item['status'] = newStatus;
      if (newStatus == 'declined') {
        _declined.insert(0, item);
      } else if (newStatus == 'completed') {
        _completed.insert(0, item);
      } else {
        _upcoming.insert(0, item);
      }
      _loading = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Ride $newStatus')));
  }

  @override
  Widget build(BuildContext context) {
    // prepare passenger→color palette
    final palette = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    final passengerColors = <String, Color>{};
    for (final m in _upcoming) {
      final name = m['passenger'] as String;
      if (!passengerColors.containsKey(name)) {
        passengerColors[name] =
            palette[passengerColors.length % palette.length];
      }
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride Matches'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Upcoming'),
              Tab(text: 'Declined'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                  controller: _tabController,
                  children: [
                    // Upcoming with colored mini‑map
                    RefreshIndicator(
                      onRefresh: _loadMatches,
                      child: ListView(
                        controller: _listScroll,
                        padding: const EdgeInsets.all(16),
                        children: [
                          SizedBox(
                            height: 200,
                            child: FlutterMap(
                              options: MapOptions(
                                center:
                                    _routePoints.isNotEmpty
                                        ? _routePoints.first
                                        : LatLng(0, 0),
                                zoom: 13,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  subdomains: const ['a', 'b', 'c'],
                                  userAgentPackageName: 'com.example.godavao',
                                ),
                                if (_routePoints.isNotEmpty)
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: _routePoints,
                                        strokeWidth: 4,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers:
                                      _upcoming.map((m) {
                                        final pt = m['pickup_point'] as LatLng;
                                        final name = m['passenger'] as String;
                                        final color = passengerColors[name]!;
                                        return Marker(
                                          point: pt,
                                          width: 32,
                                          height: 32,
                                          child: GestureDetector(
                                            onTap: () {
                                              final idx = _upcoming.indexOf(m);
                                              final offset = idx * 150.0;
                                              _listScroll.animateTo(
                                                offset,
                                                duration: const Duration(
                                                  milliseconds: 400,
                                                ),
                                                curve: Curves.easeInOut,
                                              );
                                            },
                                            child: Icon(
                                              Icons.location_on,
                                              color: color,
                                              size: 32,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ..._upcoming.map(_buildCard).toList(),
                        ],
                      ),
                    ),

                    // Declined
                    RefreshIndicator(
                      onRefresh: _loadMatches,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _declined.map(_buildCard).toList(),
                      ),
                    ),

                    // Completed
                    RefreshIndicator(
                      onRefresh: _loadMatches,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _completed.map(_buildCard).toList(),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  @override
  void dispose() {
    if (_matchChannel != null) _supabase.removeChannel(_matchChannel!);
    _tabController.dispose();
    _listScroll.dispose();
    super.dispose();
  }
}
