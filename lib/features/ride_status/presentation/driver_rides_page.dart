import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/admin_menu_action.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';

import 'package:godavao/main.dart' show localNotify;

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({super.key});

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _poly = PolylinePoints();
  final _dist = Distance();

  late TabController _tabController;
  final _listScroll = ScrollController();

  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _declined = [];
  List<Map<String, dynamic>> _completed = [];
  final Set<String> _newMatchIds = {};

  Map<String, Map<String, dynamic>> _paymentByRide = {};
  bool _loading = true;
  RealtimeChannel? _matchChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    // 1. Load driver’s latest route
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
        _upcoming = [];
        _declined = [];
        _completed = [];
        _routePoints = [];
        _paymentByRide = {};
        _loading = false;
      });
      return;
    }

    _routePoints =
        _poly
            .decodePolyline(routeData['route_polyline'] as String)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

    _subscribeToNewMatches(routeData['id'] as String);

    // 2. Fetch ride matches with nested ride_requests
    final raw = await _supabase
        .from('ride_matches')
        .select('''
          id,
          ride_request_id,
          status,
          created_at,
          ride_requests (
            pickup_lat, pickup_lng,
            destination_lat, destination_lng,
            passenger_id, fare,
            users ( id, name )
          )
        ''')
        .eq('driver_route_id', routeData['id'] as String)
        .order('created_at', ascending: true);

    final all = <Map<String, dynamic>>[];
    final rideIds = <String>[];

    for (final m in raw as List) {
      final req = m['ride_requests'] as Map<String, dynamic>?;
      if (req == null) continue;

      // passenger info
      String passengerName = 'Unknown';
      String? passengerId;
      final usersRel = req['users'];
      if (usersRel is Map) {
        passengerName = usersRel['name'] ?? passengerName;
        passengerId = usersRel['id']?.toString();
      } else if (usersRel is List && usersRel.isNotEmpty) {
        final first = usersRel.first as Map;
        passengerName = first['name'] ?? passengerName;
        passengerId = first['id']?.toString();
      }
      passengerId ??= req['passenger_id']?.toString();

      // pickup & destination
      final pickup = LatLng(
        (req['pickup_lat'] as num).toDouble(),
        (req['pickup_lng'] as num).toDouble(),
      );
      final dest = LatLng(
        (req['destination_lat'] as num).toDouble(),
        (req['destination_lng'] as num).toDouble(),
      );

      String fmt(Placemark pm) => [
        pm.thoroughfare,
        pm.subLocality,
        pm.locality,
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

      final pickupMark =
          (await placemarkFromCoordinates(
            pickup.latitude,
            pickup.longitude,
          )).first;
      final destMark =
          (await placemarkFromCoordinates(dest.latitude, dest.longitude)).first;

      // route index for sorting
      int bestI = 0;
      double bestD = double.infinity;
      for (var i = 0; i < _routePoints.length; i++) {
        final d = _dist(_routePoints[i], pickup);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }

      final fare = (req['fare'] as num?)?.toDouble();

      all.add({
        'match_id': m['id'],
        'ride_request_id': m['ride_request_id'],
        'status': m['status'],
        'created_at': m['created_at'],
        'passenger': passengerName,
        'passenger_id': passengerId,
        'pickup_point': pickup,
        'pickup_address': fmt(pickupMark),
        'destination_address': fmt(destMark),
        'route_index': bestI,
        'fare': fare,
      });

      rideIds.add(m['ride_request_id'] as String);
    }

    all.sort((a, b) => a['route_index'].compareTo(b['route_index']));
    await _loadPaymentIntents(rideIds);

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

  Future<void> _loadPaymentIntents(List<String> rideIds) async {
    _paymentByRide = {};
    if (rideIds.isEmpty) return;

    final res = await _supabase
        .from('payment_intents')
        .select('ride_id, status, amount')
        .inFilter('ride_id', rideIds.toSet().toList());

    for (final row in res as List) {
      _paymentByRide[row['ride_id']] = {
        'status': row['status'] as String?,
        'amount': (row['amount'] as num?)?.toDouble(),
      };
    }
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
                setState(
                  () => _newMatchIds.add(payload.newRecord['id'] as String),
                );
                _showNotification(
                  'New Request',
                  'A passenger requested a pickup.',
                );
                _loadMatches();
              },
            )
            .subscribe();
  }

  // === UI HELPERS ===
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

  Widget _paymentStatusBadge(String rideId) {
    final pi = _paymentByRide[rideId];
    if (pi == null) return const SizedBox.shrink();
    final status = pi['status'] ?? '';
    final amount = pi['amount'];

    Color bg;
    IconData icon;
    String label;
    switch (status) {
      case 'on_hold':
        bg = Colors.amber.shade100;
        icon = Icons.lock_clock;
        label = 'ON HOLD';
        break;
      case 'captured':
        bg = Colors.green.shade100;
        icon = Icons.verified;
        label = 'CAPTURED';
        break;
      case 'canceled':
        bg = Colors.red.shade100;
        icon = Icons.cancel;
        label = 'CANCELED';
        break;
      default:
        bg = Colors.grey.shade200;
        icon = Icons.help_outline;
        label = status.toString();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (amount != null) ...[
            const SizedBox(width: 4),
            Text('₱${amount.toStringAsFixed(2)}'),
          ],
        ],
      ),
    );
  }

  Widget _fareRow(Map<String, dynamic> m) {
    final fare = (m['fare'] as num?)?.toDouble();
    return Text(
      fare != null ? 'Fare: ₱${fare.toStringAsFixed(2)}' : 'Fare: —',
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  // update status + capture payment
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
    await _supabase
        .from('ride_requests')
        .update({'status': newStatus})
        .eq('id', rideRequestId);

    if (newStatus == 'completed') {
      await _supabase
          .from('payment_intents')
          .update({'status': 'captured'})
          .eq('ride_id', rideRequestId);
    }

    await _loadMatches();
    setState(() => _loading = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Ride $newStatus')));
  }

  // === WIDGETS ===
  Widget _buildCard(Map<String, dynamic> m) {
    final id = m['match_id'] as String;
    final status = (m['status'] as String).toLowerCase();
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(m['created_at']));
    final passengerId = m['passenger_id'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m['pickup_address']} → ${m['destination_address']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Passenger: ${m['passenger']}'),
            Text('Requested: $dt'),
            _fareRow(m),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Status: ${status.toUpperCase()}',
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _paymentStatusBadge(m['ride_request_id']),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (status == 'pending') ...[
                  ElevatedButton(
                    onPressed:
                        () => _updateMatchStatus(
                          id,
                          m['ride_request_id'],
                          'accepted',
                        ),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        () => _updateMatchStatus(
                          id,
                          m['ride_request_id'],
                          'declined',
                        ),
                    child: const Text('Decline'),
                  ),
                ],
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.message),
                  onPressed:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(matchId: id),
                        ),
                      ),
                ),
                if (status == 'completed' && passengerId != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.star),
                    label: const Text('Rate passenger'),
                    onPressed: () => _ratePassenger(m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ratePassenger(Map<String, dynamic> m) async {
    final uid = _supabase.auth.currentUser?.id;
    final rideId = m['ride_request_id']?.toString();
    final passengerId = m['passenger_id']?.toString();
    if (uid == null || rideId == null || passengerId == null) return;

    final existing = await RatingsService(_supabase).getExistingRating(
      rideId: rideId,
      raterUserId: uid,
      rateeUserId: passengerId,
    );
    if (existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already rated this passenger for this ride.'),
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => RateUserSheet(
            rideId: rideId,
            raterUserId: uid,
            rateeUserId: passengerId,
            rateeName: m['passenger'] ?? 'Passenger',
            rateeRole: 'passenger',
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          actions: [
            AdminMenuAction(),
            IconButton(
              icon: const Icon(Icons.verified_user),
              tooltip: 'Get Verified',
              onPressed:
                  () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const VerifyIdentitySheet(),
                  ),
            ),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                  controller: _tabController,
                  children: [
                    RefreshIndicator(
                      onRefresh: _loadMatches,
                      child: ListView(
                        controller: _listScroll,
                        padding: const EdgeInsets.all(16),
                        children: _upcoming.map(_buildCard).toList(),
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: _loadMatches,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _declined.map(_buildCard).toList(),
                      ),
                    ),
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
