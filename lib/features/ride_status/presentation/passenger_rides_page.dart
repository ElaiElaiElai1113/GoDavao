import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';
// import 'package:godavao/features/verify/presentation/admin_menu_action.dart'; // <- remove this import
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

class _PassengerRidesPageState extends State<PassengerRidesPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _working = false; // prevents double taps while cancelling
  String? _error;

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _history = [];

  // Theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _loadRides();
  }

  Future<String> _formatAddress(double lat, double lng) async {
    try {
      final pm = await placemarkFromCoordinates(lat, lng);
      final m = pm.first;
      final parts = <String?>[m.thoroughfare, m.subLocality, m.locality];
      return parts
          .where((s) => s != null && s!.isNotEmpty)
          .cast<String>()
          .join(', ');
    } catch (_) {
      return 'Unknown';
    }
  }

  // Safely extract driverId from a ride row (handles map or list)
  String? _extractDriverId(Map<String, dynamic> ride) {
    final rel = ride['driver_routes'];
    if (rel is Map && rel['driver_id'] != null)
      return rel['driver_id'].toString();
    if (rel is List &&
        rel.isNotEmpty &&
        rel.first is Map &&
        rel.first['driver_id'] != null) {
      return rel.first['driver_id'].toString();
    }
    return null;
  }

  Future<void> _loadRides() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'You are not signed in.';
      });
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
            enriched
                .where(
                  (r) => [
                    'pending',
                    'accepted',
                    'en_route',
                  ].contains(r['status'] as String),
                )
                .toList();

        _history =
            enriched
                .where(
                  (r) => [
                    'completed',
                    'declined',
                    'cancelled',
                    'canceled',
                  ].contains(r['status'] as String),
                )
                .toList();
      });
    } catch (e) {
      setState(() => _error = 'Failed to load rides.');
    } finally {
      setState(() => _loading = false);
    }
  }

  // -------- UI bits

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
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      default:
        return Colors.black87;
    }
  }

  Widget _statusPill(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: .3,
        ),
      ),
    );
  }

  Widget _primaryGradientButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [_purple, _purpleDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _purple.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon:
              icon == null
                  ? const SizedBox.shrink()
                  : Icon(icon, color: Colors.white, size: 18),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRide(String rideId, {String? reason}) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await supabase.rpc(
        'cancel_ride',
        params: {'p_ride_id': rideId, 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ride canceled')));
      await _loadRides();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmCancel(String rideId) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Cancel this ride?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'You can optionally tell the driver why you’re cancelling.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep Ride'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel Ride'),
              ),
            ],
          ),
    );
    if (ok == true) {
      final reason =
          reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
      await _cancelRide(rideId, reason: reason);
    }
  }

  Widget _buildCard(Map<String, dynamic> ride, {required bool upcoming}) {
    final dt = DateFormat(
      'MMM d, y • h:mm a',
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mini-map preview (OSRM with fallback line)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
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
                                  color: Colors.purple.shade700,
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
                                  color: Colors.purple.shade700,
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
                          userAgentPackageName: 'com.godavao.app',
                        ),
                        routeLayer,
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(pLat, pLng),
                              width: 28,
                              height: 28,
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.purple,
                              ),
                            ),
                            Marker(
                              point: LatLng(dLat, dLng),
                              width: 28,
                              height: 28,
                              child: const Icon(Icons.flag, color: Colors.red),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Addresses (constrain long strings)
            Text(
              '${ride['pickup_address']} → ${ride['destination_address']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),

            // Driver row + rating badge (if assigned)
            Row(
              children: [
                const Icon(
                  Icons.directions_car,
                  size: 14,
                  color: Colors.black54,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Driver: ${driverId ?? 'unassigned'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (driverId != null)
                  UserRatingBadge(userId: driverId, iconSize: 14),
              ],
            ),
            const SizedBox(height: 4),

            // Fare + time
            Row(
              children: [
                Text(
                  '₱${fare.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.access_time, size: 14, color: Colors.black54),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    dt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _statusPill(status),

            const SizedBox(height: 10),

            // Actions
            if (upcoming)
              Row(
                children: [
                  if (status == 'pending' || status == 'accepted')
                    Expanded(
                      child: _primaryGradientButton(
                        label: _working ? 'Cancelling…' : 'Cancel Ride',
                        icon: Icons.close,
                        onPressed: () => _confirmCancel(ride['id'] as String),
                      ),
                    ),
                  if (status == 'accepted' || status == 'en_route') ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _primaryGradientButton(
                        label: 'Contact Driver',
                        icon: Icons.phone,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contacting driver…')),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
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
                icon: const Icon(Icons.chevron_right),
                label: const Text(
                  'View details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(foregroundColor: _purple),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Scaffold ----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('My Rides'),
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('My Rides'),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          actions: const [
            _AdminMenuButton(), // <- SAFE replacement
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    tabBarTheme: const TabBarThemeData(
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.black87,
                      indicatorSize: TabBarIndicatorSize.tab,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const TabBar(
                      indicator: BoxDecoration(
                        color: Color(0xFF6A27F7),
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                      tabs: [Tab(text: 'Upcoming'), Tab(text: 'History')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
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
}

/// Small, AppBar-safe popup menu (no ListTile, no unbounded width)
class _AdminMenuButton extends StatelessWidget {
  const _AdminMenuButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Admin',
      icon: const Icon(Icons.admin_panel_settings),
      onSelected: (value) {
        // TODO: navigate to your admin pages depending on value
        // e.g. if (value == 'verification') { Navigator.push(...); }
      },
      itemBuilder:
          (ctx) => const [
            PopupMenuItem(
              value: 'verification',
              child: Text('Verification Review'),
            ),
            PopupMenuItem(
              value: 'vehicle',
              child: Text('Vehicle Verification'),
            ),
          ],
    );
  }
}
