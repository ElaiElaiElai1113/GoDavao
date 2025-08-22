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

  Map<String, Map<String, dynamic>> _paymentByRide = {};
  bool _loading = true;
  RealtimeChannel? _matchChannel;

  // theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMatches();
  }

  // --- Actions ---------------------------------------------------------------

  Future<void> _acceptViaRpc(String matchId, String rideRequestId) async {
    setState(() => _loading = true);
    try {
      await _supabase.rpc('accept_match', params: {'p_match_id': matchId});
      await _loadPaymentIntents([rideRequestId]);
      setState(() {
        final item = _findAndRemove(matchId);
        if (item != null) {
          item['status'] = 'accepted';
          _upcoming.insert(0, item);
        }
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ride accepted')));
      }
    } on PostgrestException catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Accept failed: $e')));
    }
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

    _subscribeToNewMatchesByDriver(user.id);

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
        .order('created_at', ascending: false);

    final all = <Map<String, dynamic>>[];
    final rideIds = <String>[];

    for (final row in (raw as List)) {
      final m = (row as Map).cast<String, dynamic>();
      final req = (m['ride_requests'] as Map?)?.cast<String, dynamic>();
      if (req == null) continue;

      // passenger
      String passengerName = 'Unknown';
      String? passengerId;
      final usersRel = req['users'];
      if (usersRel is Map) {
        passengerName = (usersRel['name'] as String?) ?? passengerName;
        passengerId = usersRel['id']?.toString();
      } else if (usersRel is List &&
          usersRel.isNotEmpty &&
          usersRel.first is Map) {
        final first = (usersRel.first as Map).cast<String, dynamic>();
        passengerName = (first['name'] as String?) ?? passengerName;
        passengerId = first['id']?.toString();
      }
      passengerId ??= req['passenger_id']?.toString();

      // reverse geocode (best effort)
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

    for (final row in (res as List)) {
      final r = (row as Map).cast<String, dynamic>();
      _paymentByRide[r['ride_id'] as String] = {
        'status': r['status'] as String?,
        'amount': (r['amount'] as num?)?.toDouble(),
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
              callback: (payload) {
                final newRec = payload.newRecord;
                if (newRec == null) return;
                final rec = (newRec as Map).cast<String, dynamic>();
                if (rec['driver_id']?.toString() != driverId) return;

                setState(() => _newMatchIds.add(rec['id']?.toString() ?? ''));
                _showNotification(
                  'New Request',
                  'A passenger requested a pickup.',
                );
                _loadMatches();
              },
            )
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_matches',
              event: PostgresChangeEvent.update,
              callback: (payload) {
                final newRec = payload.newRecord;
                if (newRec == null) return;
                final rec = (newRec as Map).cast<String, dynamic>();
                if (rec['driver_id']?.toString() != driverId) return;
                _loadMatches();
              },
            )
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_matches',
              event: PostgresChangeEvent.delete,
              callback: (payload) {
                final oldRec = payload.oldRecord;
                if (oldRec == null) return;
                final rec = (oldRec as Map).cast<String, dynamic>();
                if (rec['driver_id']?.toString() != driverId) return;
                _loadMatches();
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
        const SnackBar(content: Text('You already rated this passenger.')),
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

  // --- UI --------------------------------------------------------------------

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

  Widget _pill(String text, {IconData? icon, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey.shade100).withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.black54),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required Widget child,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 40,
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
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onPressed,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> m) {
    final id = m['match_id'] as String;
    final status = (m['status'] as String).toLowerCase();
    final dt = DateFormat(
      'MMM d, y • h:mm a',
    ).format(DateTime.parse(m['created_at']));
    final passengerId = m['passenger_id'] as String?;
    final rideRequestId = m['ride_request_id'] as String;
    final isNew = _newMatchIds.remove(id);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top row: route + NEW
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${m['pickup_address']} → ${m['destination_address']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // meta row
            Row(
              children: [
                if (m['driver_route_id'] != null)
                  _pill(
                    'Route ${m['driver_route_id'].toString().substring(0, 8)}',
                    icon: Icons.alt_route,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Colors.black54),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          m['passenger'] ?? 'Passenger',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (passengerId != null) ...[
                        const SizedBox(width: 6),
                        VerifiedBadge(userId: passengerId, size: 16),
                        const SizedBox(width: 6),
                        UserRatingBadge(userId: passengerId, iconSize: 14),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // time + fare
            Row(
              children: [
                _pill(dt, icon: Icons.access_time),
                const SizedBox(width: 8),
                if (m['fare'] != null)
                  _pill(
                    '₱${(m['fare'] as num).toDouble().toStringAsFixed(2)}',
                    icon: Icons.payments,
                  ),
                const Spacer(),
                PaymentStatusChip(
                  status: _paymentByRide[rideRequestId]?['status'] as String?,
                  amount: _paymentByRide[rideRequestId]?['amount'] as double?,
                ),
              ],
            ),

            const Divider(height: 18),

            // status + actions
            Row(
              children: [
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),

                // actions
                if (status == 'pending') ...[
                  SizedBox(
                    width: 120,
                    child: _primaryButton(
                      child: const Text('Accept'),
                      onPressed: () => _acceptViaRpc(id, rideRequestId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        () => _updateMatchStatus(id, rideRequestId, 'declined'),
                    child: const Text('Decline'),
                  ),
                ] else if (status == 'accepted') ...[
                  SizedBox(
                    width: 150,
                    child: _primaryButton(
                      child: const Text('Start Ride'),
                      onPressed:
                          () =>
                              _updateMatchStatus(id, rideRequestId, 'en_route'),
                    ),
                  ),
                ] else if (status == 'en_route') ...[
                  SizedBox(
                    width: 170,
                    child: _primaryButton(
                      child: const Text('Complete Ride'),
                      onPressed:
                          () => _updateMatchStatus(
                            id,
                            rideRequestId,
                            'completed',
                          ),
                    ),
                  ),
                ] else if (status == 'completed' && passengerId != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.star),
                    label: const Text('Rate passenger'),
                    onPressed: () => _ratePassenger(m),
                  ),
                ],

                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Open chat',
                  icon: const Icon(Icons.message_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatPage(matchId: id)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Scaffold --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final counters = [_upcoming.length, _declined.length, _completed.length];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Ride Matches'),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(999),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black87,
                dividerColor: Colors.transparent,
                tabs: [
                  _segTab('Upcoming', counters[0]),
                  _segTab('Declined', counters[1]),
                  _segTab('Completed', counters[2]),
                ],
              ),
            ),
          ),
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  _list(_upcoming),
                  _list(_declined),
                  _list(_completed),
                ],
              ),
    );
  }

  Tab _segTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items) {
    return RefreshIndicator(
      onRefresh: _loadMatches,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildCard(items[i]),
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
