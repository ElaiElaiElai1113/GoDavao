import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:godavao/features/ride_status/presentation/driver_ride_status_page.dart';
import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';
import 'package:godavao/features/verify/presentation/admin_menu_action.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// OSRM
import 'package:godavao/core/osrm_service.dart';

import 'package:godavao/features/ratings/presentation/user_rating.dart';

class PassengerRidesPage extends StatefulWidget {
  const PassengerRidesPage({super.key});

  @override
  State<PassengerRidesPage> createState() => _PassengerRidesPageState();
}

class _PassengerRidesPageState extends State<PassengerRidesPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  bool _loading = true;

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRides();
  }

  Future<String> _formatAddress(double lat, double lng) async {
    try {
      final pm = await placemarkFromCoordinates(lat, lng);
      final m = pm.first;
      final parts = <String?>[m.thoroughfare, m.subLocality, m.locality];
      return parts
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .join(', ');
    } catch (_) {
      return 'Unknown';
    }
  }

  // Safely extract driverId from a ride row (handles map or list)
  String? _extractDriverId(Map<String, dynamic> ride) {
    final rel = ride['driver_routes'];
    if (rel is Map && rel['driver_id'] != null) {
      return rel['driver_id'].toString();
    }
    if (rel is List &&
        rel.isNotEmpty &&
        rel.first is Map &&
        rel.first['driver_id'] != null) {
      return rel.first['driver_id'].toString();
    }
    return null;
  }

  Future<void> _loadRides() async {
    setState(() => _loading = true);
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final data = await supabase
          .from('ride_requests')
          .select(r'''
    id,
    pickup_lat,
    pickup_lng,
    destination_lat,
    destination_lng,
    fare,
    status,
    created_at,
    driver_route_id,
    driver_routes ( id, driver_id )
  ''')
          .eq('passenger_id', user.id)
          .order('created_at', ascending: false);

      final raw =
          (data as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      final enriched = await Future.wait(
        raw.map((ride) async {
          final pLat = (ride['pickup_lat'] as num).toDouble();
          final pLng = (ride['pickup_lng'] as num).toDouble();
          final dLat = (ride['destination_lat'] as num).toDouble();
          final dLng = (ride['destination_lng'] as num).toDouble();
          return {
            ...ride,
            'pickup_address': await _formatAddress(pLat, pLng),
            'destination_address': await _formatAddress(dLat, dLng),
          };
        }),
      );

      setState(() {
        _upcoming =
            enriched.where((r) {
              final st = r['status'] as String;
              return ['pending', 'accepted', 'en_route'].contains(st);
            }).toList();
        _history =
            enriched.where((r) {
              final st = r['status'] as String;
              return ['completed', 'declined', 'cancelled'].contains(st);
            }).toList();
      });
    } catch (e) {
      debugPrint('Error loading rides: $e');
    } finally {
      setState(() => _loading = false);
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

  Widget _buildCard(Map<String, dynamic> ride, {required bool upcoming}) {
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(ride['created_at'] as String));
    final status = (ride['status'] as String);
    final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;

    final pLat = (ride['pickup_lat'] as num).toDouble();
    final pLng = (ride['pickup_lng'] as num).toDouble();
    final dLat = (ride['destination_lat'] as num).toDouble();
    final dLng = (ride['destination_lng'] as num).toDouble();

    final driverId = _extractDriverId(ride);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // OSRM-powered mini map preview
            SizedBox(
              height: 120,
              child: FutureBuilder<Polyline>(
                future: fetchOsrmRoute(
                  start: LatLng(pLat, pLng),
                  end: LatLng(dLat, dLng),
                ),
                builder: (ctx, snap) {
                  final routeLayer =
                      snap.hasData
                          ? PolylineLayer(
                            polylines: [
                              Polyline(
                                points: snap.data!.points,
                                strokeWidth: 3,
                                color: Colors.green.shade700,
                              ),
                            ],
                          )
                          : PolylineLayer(
                            polylines: [
                              Polyline(
                                points: [
                                  LatLng(pLat, pLng),
                                  LatLng(dLat, dLng),
                                ],
                                strokeWidth: 3,
                                color: Colors.green.shade700,
                              ),
                            ],
                          );

                  return FlutterMap(
                    options: MapOptions(
                      center: LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
                      zoom: 13,
                      interactiveFlags: InteractiveFlag.none,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                        userAgentPackageName: 'com.example.godavao',
                      ),
                      routeLayer,
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(pLat, pLng),
                            width: 30,
                            height: 30,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.green,
                            ),
                          ),
                          Marker(
                            point: LatLng(dLat, dLng),
                            width: 30,
                            height: 30,
                            child: const Icon(Icons.flag, color: Colors.red),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // addresses & fare
            Text(
              '${ride['pickup_address']} → ${ride['destination_address']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            // NEW: Driver row with rating badge
            Row(
              children: [
                Expanded(child: Text('Driver: ${driverId ?? 'unassigned'}')),
                if (driverId != null)
                  UserRatingBadge(userId: driverId, iconSize: 14),
              ],
            ),

            const SizedBox(height: 4),
            Text('Fare: ₱${fare.toStringAsFixed(2)}'),
            Text('Requested: $dt'),
            const SizedBox(height: 4),

            // status pill
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // action buttons (only for upcoming)
            if (upcoming)
              Row(
                children: [
                  if (status == 'pending')
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await supabase
                              .from('ride_requests')
                              .update({'status': 'cancelled'})
                              .eq('id', ride['id']);
                          _loadRides();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Cancel Ride'),
                      ),
                    ),
                  if (status == 'accepted' || status == 'en_route') ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contacting driver…')),
                          );
                        },
                        icon: const Icon(Icons.phone),
                        label: const Text('Contact Driver'),
                      ),
                    ),
                  ],
                ],
              ),

            // view details arrow
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => PassengerRideStatusPage(
                            rideId: ride['id'] as String,
                          ),
                    ),
                  );
                },
              ),
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Rides'),
          actions: [
            AdminMenuAction(),
            IconButton(
              icon: const Icon(Icons.verified_user),
              tooltip: 'Get Verified',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const VerifyIdentitySheet(),
                );
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Upcoming'), Tab(text: 'History')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            RefreshIndicator(
              onRefresh: _loadRides,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children:
                    _upcoming
                        .map((r) => _buildCard(r, upcoming: true))
                        .toList(),
              ),
            ),
            RefreshIndicator(
              onRefresh: _loadRides,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children:
                    _history
                        .map((r) => _buildCard(r, upcoming: false))
                        .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
