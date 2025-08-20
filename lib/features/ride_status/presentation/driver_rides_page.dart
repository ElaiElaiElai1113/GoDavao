import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
import 'package:godavao/features/payments/presentation/payment_status_chip.dart';
import 'package:godavao/main.dart' show localNotify;

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({super.key});
  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  late TabController _tabController;
  final _listScroll = ScrollController();

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _declined = [];
  List<Map<String, dynamic>> _completed = [];
  final Set<String> _newMatchIds = {};

  // ride_request_id -> {status, amount}
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

    // Subscribe to ALL matches for this driver (once)
    _subscribeToNewMatchesByDriver(user.id);

    // Fetch ALL ride_matches for this driver, regardless of route
    final raw = await _supabase
        .from('ride_matches')
        .select('''
          id,
          ride_request_id,
          status,
          created_at,
          driver_id,
          driver_route_id,
          ride_requests (
            pickup_lat, pickup_lng,
            destination_lat, destination_lng,
            passenger_id, fare,
            users ( id, name )
          )
        ''')
        .eq('driver_id', user.id)
        .order('created_at', ascending: false); // newest first

    final all = <Map<String, dynamic>>[];
    final rideIds = <String>[];

    for (final m in raw as List) {
      final req = m['ride_requests'] as Map<String, dynamic>?;
      if (req == null) continue;

      // Passenger name/id
      String passengerName = 'Unknown';
      String? passengerId;
      final usersRel = req['users'];
      if (usersRel is Map) {
        passengerName = (usersRel['name'] as String?) ?? passengerName;
        passengerId = usersRel['id']?.toString();
      } else if (usersRel is List &&
          usersRel.isNotEmpty &&
          usersRel.first is Map) {
        final first = usersRel.first as Map;
        passengerName = (first['name'] as String?) ?? passengerName;
        passengerId = first['id']?.toString();
      }
      passengerId ??= req['passenger_id']?.toString();

      // Addresses (best effort reverse geocode)
      String fmt(Placemark pm) => [
        pm.thoroughfare,
        pm.subLocality,
        pm.locality,
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

      String pickupAddr = 'Pickup';
      String destAddr = 'Destination';
      try {
        final pickupMark =
            (await placemarkFromCoordinates(
              (req['pickup_lat'] as num).toDouble(),
              (req['pickup_lng'] as num).toDouble(),
            )).first;
        pickupAddr = fmt(pickupMark);
      } catch (_) {}
      try {
        final destMark =
            (await placemarkFromCoordinates(
              (req['destination_lat'] as num).toDouble(),
              (req['destination_lng'] as num).toDouble(),
            )).first;
        destAddr = fmt(destMark);
      } catch (_) {}

      final fare = (req['fare'] as num?)?.toDouble();

      all.add({
        'match_id': m['id'],
        'ride_request_id': m['ride_request_id'],
        'driver_route_id': m['driver_route_id'],
        'status': m['status'],
        'created_at': m['created_at'],
        'passenger': passengerName,
        'passenger_id': passengerId,
        'pickup_address': pickupAddr,
        'destination_address': destAddr,
        'fare': fare,
      });

      rideIds.add(m['ride_request_id'] as String);
    }

    // Load payment badges in bulk
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
      _paymentByRide[row['ride_id'] as String] = {
        'status': row['status'] as String?,
        'amount': (row['amount'] as num?)?.toDouble(),
      };
    }
  }

  void _subscribeToNewMatchesByDriver(String driverId) {
    if (_matchChannel != null) return;
    _matchChannel =
        _supabase
            .channel('ride_matches_driver_$driverId')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_matches',
              event: PostgresChangeEvent.insert,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'driver_id',
                value: driverId, // 🔑 watch all routes for this driver
              ),
              callback: (payload) {
                setState(
                  () => _newMatchIds.add(payload.newRecord['id'] as String),
                );
                _showNotification(
                  'New Request',
                  'A passenger requested a pickup.',
                );
                _loadMatches(); // refresh list
              },
            )
            .subscribe();
  }

  Map<String, dynamic>? _findAndRemove(String matchId) {
    final i1 = _upcoming.indexWhere((e) => e['match_id'] == matchId);
    if (i1 != -1) return _upcoming.removeAt(i1);
    final i2 = _declined.indexWhere((e) => e['match_id'] == matchId);
    if (i2 != -1) return _declined.removeAt(i2);
    final i3 = _completed.indexWhere((e) => e['match_id'] == matchId);
    if (i3 != -1) return _completed.removeAt(i3);
    return null;
  }

  Future<void> _syncPaymentForRide(
    String rideRequestId,
    String newStatus,
  ) async {
    try {
      if (newStatus == 'completed') {
        await _supabase
            .from('payment_intents')
            .update({'status': 'captured'})
            .eq('ride_id', rideRequestId);
      } else if (newStatus == 'declined' || newStatus == 'canceled') {
        await _supabase
            .from('payment_intents')
            .update({'status': 'canceled'})
            .eq('ride_id', rideRequestId);
      }
    } catch (_) {
      // non-fatal
    } finally {
      await _loadPaymentIntents([rideRequestId]);
      if (mounted) setState(() {});
    }
  }

  Future<void> _updateMatchStatus(
    String matchId,
    String rideRequestId,
    String newStatus,
  ) async {
    setState(() => _loading = true);

    try {
      // 1) match
      await _supabase
          .from('ride_matches')
          .update({'status': newStatus})
          .eq('id', matchId);

      // 2) mirror to ride_requests (+ attach latest route_id on accept, optional)
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

      // 3) payments
      if (newStatus == 'completed' ||
          newStatus == 'declined' ||
          newStatus == 'canceled') {
        await _syncPaymentForRide(rideRequestId, newStatus);
      }

      setState(() {
        final item = _findAndRemove(matchId);
        if (item != null) {
          item['status'] = newStatus;
          if (newStatus == 'declined' || newStatus == 'canceled') {
            _declined.insert(0, item);
          } else if (newStatus == 'completed') {
            _completed.insert(0, item);
          } else {
            _upcoming.insert(0, item);
          }
        }
        _loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ride $newStatus')));
      }
    } catch (e) {
      if (mounted) {
        _loading = false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
        setState(() {});
      }
    }
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

  Widget _buildCard(Map<String, dynamic> m) {
    final id = m['match_id'] as String;
    final status = (m['status'] as String).toLowerCase();
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(m['created_at']));
    final passengerId = m['passenger_id'] as String?;
    final rideRequestId = m['ride_request_id'] as String;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
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
            Row(
              children: [
                if (m['driver_route_id'] != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Route: ${m['driver_route_id'].toString().substring(0, 8)}',
                    ),
                  ),
                ],
                Expanded(child: Text('Passenger: ${m['passenger']}')),
                if (passengerId != null) ...[
                  const SizedBox(width: 6),
                  VerifiedBadge(userId: passengerId, size: 16),
                  const SizedBox(width: 6),
                  UserRatingBadge(userId: passengerId, iconSize: 14),
                ],
              ],
            ),
            Text('Requested: $dt'),
            const SizedBox(height: 8),
            Text(
              (m['fare'] as num?) != null
                  ? 'Fare: ₱${(m['fare'] as num).toDouble().toStringAsFixed(2)}'
                  : 'Fare: —',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
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
                PaymentStatusChip(
                  status: _paymentByRide[rideRequestId]?['status'] as String?,
                  amount: _paymentByRide[rideRequestId]?['amount'] as double?,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (status == 'pending') ...[
                  ElevatedButton(
                    onPressed:
                        () => _updateMatchStatus(id, rideRequestId, 'accepted'),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        () => _updateMatchStatus(id, rideRequestId, 'declined'),
                    child: const Text('Decline'),
                  ),
                ],
                if (status == 'accepted')
                  ElevatedButton(
                    onPressed:
                        () => _updateMatchStatus(id, rideRequestId, 'en_route'),
                    child: const Text('Start Ride'),
                  ),
                if (status == 'en_route')
                  ElevatedButton(
                    onPressed:
                        () =>
                            _updateMatchStatus(id, rideRequestId, 'completed'),
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
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const VerifyIdentitySheet(),
                );
              },
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
