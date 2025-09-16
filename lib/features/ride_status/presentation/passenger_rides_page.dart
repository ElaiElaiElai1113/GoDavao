// lib/features/ride_status/presentation/passenger_rides_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/core/reverse_geocoder.dart';
import 'package:godavao/core/osrm_service.dart';

import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';

class PassengerRidesPage extends StatefulWidget {
  const PassengerRidesPage({super.key});

  @override
  State<PassengerRidesPage> createState() => _PassengerRidesPageState();
}

class _PassengerRidesPageState extends State<PassengerRidesPage> {
  final sb = Supabase.instance.client;

  // UI state
  bool _loading = true;
  bool _working = false; // prevent double actions
  String? _error;

  // Data
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _history = [];

  // Realtime sub
  StreamSubscription<List<Map<String, dynamic>>>? _ridesSub;

  // Tiny address cache to avoid repeated reverse-geocoding
  final Map<String, String> _addrCache = {}; // key: "lat,lng" -> text

  // Theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ridesSub?.cancel();
    super.dispose();
  }

  /* ------------------------------ BOOTSTRAP ------------------------------ */
  String? _driverNameFromRel(Map<String, dynamic> ride) {
    final rel = ride['driver_routes'];

    if (rel is Map) {
      final u = rel['users'];
      if (u is Map && u['name'] != null) return u['name'].toString();
    }
    if (rel is List && rel.isNotEmpty) {
      final u = rel.first['users'];
      if (u is Map && u['name'] != null) return u['name'].toString();
    }
    return null;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final me = sb.auth.currentUser;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'You are not signed in.';
      });
      return;
    }

    // 1) Prime with an initial fetch (so the page isn’t blank on first paint)
    try {
      final rows = await sb
          .from('ride_requests')
          .select('''
      id, status, created_at, fare,
      pickup_lat, pickup_lng, destination_lat, destination_lng,
      driver_route_id,
      driver_routes (
        id, driver_id,
        users!driver_routes_driver_id_fkey ( id, name )
      )
    ''')
          .eq('passenger_id', me.id);

      await _ingestRows(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
    } catch (e) {
      setState(() => _error = 'Failed to load rides.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    // 2) Realtime stream (no .order() on streams; we sort locally)
    _ridesSub?.cancel();
    _ridesSub = sb
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('passenger_id', me.id)
        .listen((rows) async {
          await _ingestRows(
            rows.map((e) => Map<String, dynamic>.from(e)).toList(),
          );
        });
  }

  /* ------------------------------ INGEST ------------------------------ */

  Future<void> _ingestRows(List<Map<String, dynamic>> rows) async {
    // Enrich with human-readable addresses (cached)
    Future<String> addr(double lat, double lng) async {
      final key = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
      final cached = _addrCache[key];
      if (cached != null) return cached;
      final text = await reverseGeocodeText(lat, lng);
      _addrCache[key] = text;
      return text;
    }

    final enriched = await Future.wait(
      rows.map((r) async {
        final pLat = (r['pickup_lat'] as num).toDouble();
        final pLng = (r['pickup_lng'] as num).toDouble();
        final dLat = (r['destination_lat'] as num).toDouble();
        final dLng = (r['destination_lng'] as num).toDouble();

        return {
          ...r,
          'pickup_address': await addr(pLat, pLng),
          'destination_address': await addr(dLat, dLng),
        };
      }),
    );

    // Sort newest first
    enriched.sort(
      (a, b) => DateTime.parse(
        b['created_at'].toString(),
      ).compareTo(DateTime.parse(a['created_at'].toString())),
    );

    // Partition into upcoming vs history by status
    List<String> up = const ['pending', 'accepted', 'en_route'];
    List<String> hist = const [
      'completed',
      'declined',
      'cancelled',
      'canceled',
    ];

    if (!mounted) return;
    setState(() {
      _upcoming =
          enriched.where((r) => up.contains(r['status'] as String)).toList();
      _history =
          enriched.where((r) => hist.contains(r['status'] as String)).toList();
    });
  }

  /* ------------------------------ ACTIONS ------------------------------ */

  Future<void> _cancelRide(String rideId, {String? reason}) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await sb.rpc(
        'cancel_ride',
        params: {'p_ride_id': rideId, 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ride canceled')));
      // Stream will update the list for us; no manual reload needed
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
    final ctrl = TextEditingController();
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
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
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
      final reason = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
      await _cancelRide(rideId, reason: reason);
    }
  }

  /* ------------------------------ UI HELPERS ------------------------------ */

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    IconData? icon,
    required VoidCallback? onPressed,
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
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
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

  String _peso(num? v) =>
      v == null ? '₱0.00' : '₱${v.toDouble().toStringAsFixed(2)}';

  String? _driverIdFromRel(Map<String, dynamic> ride) {
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

  Widget _rideCard(Map<String, dynamic> ride, {required bool upcoming}) {
    final status = (ride['status'] as String).toLowerCase();
    final created = DateFormat(
      'MMM d, y • h:mm a',
    ).format(DateTime.parse(ride['created_at'].toString()));

    final fare = (ride['fare'] as num?)?.toDouble();
    final pLat = (ride['pickup_lat'] as num).toDouble();
    final pLng = (ride['pickup_lng'] as num).toDouble();
    final dLat = (ride['destination_lat'] as num).toDouble();
    final dLng = (ride['destination_lng'] as num).toDouble();
    final driverId = _driverIdFromRel(ride);

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
            // Mini map
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
                    final polylines = <Polyline>[
                      if (snap.hasData && snap.data != null)
                        snap.data!
                      else
                        Polyline(
                          points: [LatLng(pLat, pLng), LatLng(dLat, dLng)],
                          strokeWidth: 3,
                          color: Colors.purple.shade700,
                        ),
                    ];
                    return FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(
                          (pLat + dLat) / 2,
                          (pLng + dLng) / 2,
                        ),
                        initialZoom: 13,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                          userAgentPackageName: 'com.godavao.app',
                        ),
                        PolylineLayer(polylines: polylines),
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

            // Addresses
            Text(
              '${ride['pickup_address']} → ${ride['destination_address']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),

            // Meta (driver, fare, time)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.directions_car,
                      size: 14,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      driverId == null
                          ? 'Driver: unassigned'
                          : 'Driver: ${_driverNameFromRel(ride) ?? driverId.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),

                    if (driverId != null) ...[
                      const SizedBox(width: 6),
                      UserRatingBadge(userId: driverId, iconSize: 14),
                    ],
                  ],
                ),
                if (fare != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.payments,
                        size: 14,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _peso(fare),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 14,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      created,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
                _statusPill(status),
              ],
            ),

            const SizedBox(height: 10),

            // Actions
            if (upcoming)
              Row(
                children: [
                  if (status == 'pending' || status == 'accepted')
                    Expanded(
                      child: _primaryButton(
                        label: _working ? 'Cancelling…' : 'Cancel Ride',
                        icon: Icons.close,
                        onPressed: () => _confirmCancel(ride['id'].toString()),
                      ),
                    ),
                  if (status == 'accepted' || status == 'en_route') ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _primaryButton(
                        label: 'Contact Driver',
                        icon: Icons.phone,
                        onPressed: () {
                          // wire up your call/text flow here
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
                            rideId: ride['id'].toString(),
                          ),
                    ),
                  );
                },
                icon: const Icon(Icons.chevron_right),
                label: const Text('View details'),
                style: TextButton.styleFrom(foregroundColor: _purple),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ------------------------------ SCAFFOLD ------------------------------ */

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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
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
                      color: _purple,
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.black87,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: [Tab(text: 'Upcoming'), Tab(text: 'History')],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _bootstrap,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children:
                    _upcoming.map((r) => _rideCard(r, upcoming: true)).toList(),
              ),
            ),
            RefreshIndicator(
              onRefresh: _bootstrap,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children:
                    _history.map((r) => _rideCard(r, upcoming: false)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
