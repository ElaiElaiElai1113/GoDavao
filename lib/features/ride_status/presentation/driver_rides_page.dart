// lib/features/ride_status/presentation/driver_rides_page.dart
import 'dart:collection';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Maps
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

// ➕ Live location (preview-only)
import 'package:geolocator/geolocator.dart';

import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/payments/presentation/payment_status_chip.dart';
import 'package:godavao/main.dart' show localNotify;
import 'package:godavao/features/ride_status/presentation/driver_ride_status_page.dart';

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({super.key});
  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

/* ────────────────────────────────────────────────────────────────────────── */
/* Models                                                                     */
/* ────────────────────────────────────────────────────────────────────────── */

class MatchCard {
  final String matchId;
  final String rideRequestId;
  final String? driverRouteId;
  final String status; // pending | accepted | en_route | declined | completed
  final DateTime createdAt;

  final String passengerName;
  final String? passengerId;
  final String pickupAddress;
  final String destinationAddress;
  final double? fare;
  final int pax;

  // Map coords
  final double? pickupLat;
  final double? pickupLng;
  final double? destLat;
  final double? destLng;

  const MatchCard({
    required this.matchId,
    required this.rideRequestId,
    required this.driverRouteId,
    required this.status,
    required this.createdAt,
    required this.passengerName,
    required this.passengerId,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.fare,
    required this.pax,
    this.pickupLat,
    this.pickupLng,
    this.destLat,
    this.destLng,
  });

  bool get hasCoords =>
      pickupLat != null &&
      pickupLng != null &&
      destLat != null &&
      destLng != null;

  LatLng? get pickup => hasCoords ? LatLng(pickupLat!, pickupLng!) : null;
  LatLng? get destination => hasCoords ? LatLng(destLat!, destLng!) : null;
}

class RouteGroup {
  final String routeId; // "unassigned" for nulls
  int? capacityTotal;
  int? capacityAvailable;
  final List<MatchCard> items;
  final Set<String> selected = {};

  RouteGroup({
    required this.routeId,
    required this.items,
    this.capacityTotal,
    this.capacityAvailable,
  });

  List<MatchCard> byStatus(String s) =>
      items.where((m) => m.status == s).toList();

  int get acceptedSeats =>
      items.where((m) => m.status == 'accepted').fold(0, (a, b) => a + b.pax);

  int get pendingSeatsSelected => items
      .where((m) => selected.contains(m.matchId) && m.status == 'pending')
      .fold(0, (a, b) => a + b.pax);
}

/* ────────────────────────────────────────────────────────────────────────── */

class _DriverRidesPageState extends State<DriverRidesPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  static const bool _DBG = true;
  void _d(Object? msg) {
    if (_DBG) {
      // ignore: avoid_print
      print('[DriverRides] $msg');
    }
  }

  late final TabController _tabController;
  final _listScroll = ScrollController();

  // Buckets (for Declined/Completed tabs)
  List<MatchCard> _declined = [];
  List<MatchCard> _completed = [];

  // Grouped upcoming (pending | accepted | en_route) by route
  final LinkedHashMap<String, RouteGroup> _routeGroups = LinkedHashMap();

  // Owned route IDs (driver authored)
  final Set<String> _myRouteIds = {};

  // NEW tracking + tab badges
  final Set<String> _newMatchIds = {};
  int _badgeUpcoming = 0;
  int _badgeDeclined = 0;
  int _badgeCompleted = 0;

  // ride_id -> {status, amount}
  Map<String, Map<String, dynamic>> _paymentByRide = {};

  bool _loading = true;

  RealtimeChannel? _matchChannel;
  RealtimeChannel? _feeChannel;

  double _platformFeeRate = 0.15;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    _initFee();
    _refreshMyRouteIds().then((_) async {
      await _loadMatches();
      _subscribeToRideMatches();
    });
  }

  @override
  void dispose() {
    if (_matchChannel != null) _supabase.removeChannel(_matchChannel!);
    if (_feeChannel != null) _supabase.removeChannel(_feeChannel!);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  /* ───────────── Platform fee ───────────── */

  Future<void> _initFee() async {
    await _loadFeeFromDb();
    _subscribeFee();
  }

  Future<void> _loadFeeFromDb() async {
    try {
      final row =
          await _supabase
              .from('app_settings')
              .select('key, value, value_num')
              .eq('key', 'platform_fee_rate')
              .maybeSingle();
      final rate = _parseFeeRate(row as Map?);
      if (rate != null && rate >= 0 && rate <= 1) {
        setState(() => _platformFeeRate = rate);
      }
    } catch (e) {
      _d('fee load error: $e');
    }
  }

  void _subscribeFee() {
    if (_feeChannel != null) return;
    _feeChannel =
        _supabase.channel('app_settings:platform_fee_rate')
          ..onPostgresChanges(
            schema: 'public',
            table: 'app_settings',
            event: PostgresChangeEvent.insert,
            callback: (payload) {
              final rec = payload.newRecord as Map?;
              if (rec?['key']?.toString() != 'platform_fee_rate') return;
              final rate = _parseFeeRate(rec);
              if (rate != null && rate >= 0 && rate <= 1) {
                setState(() => _platformFeeRate = rate);
              }
            },
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'app_settings',
            event: PostgresChangeEvent.update,
            callback: (payload) {
              final rec = payload.newRecord as Map?;
              if (rec?['key']?.toString() != 'platform_fee_rate') return;
              final rate = _parseFeeRate(rec);
              if (rate != null && rate >= 0 && rate <= 1) {
                setState(() => _platformFeeRate = rate);
              }
            },
          )
          ..subscribe();
  }

  double? _parseFeeRate(Map? row) {
    if (row == null) return null;
    final num? n = row['value_num'] as num? ?? row['value'] as num?;
    if (n != null) return n.toDouble();
    final s = row['value']?.toString();
    return s == null ? null : double.tryParse(s);
  }

  /* ───────────── My routes ───────────── */

  Future<void> _refreshMyRouteIds() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _supabase
          .from('driver_routes')
          .select('id')
          .eq('driver_id', uid);
      final ids =
          (rows as List)
              .map((r) => (r as Map)['id']?.toString())
              .whereType<String>()
              .toList();
      _myRouteIds
        ..clear()
        ..addAll(ids);
      _d('my routes: $_myRouteIds');
    } catch (e) {
      _d('refreshMyRouteIds error: $e');
    }
  }

  /* ───────────── Notifications ───────────── */

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

  /* ───────────── Load & subscribe ───────────── */

  Future<void> _loadMatches() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (mounted) setState(() => _loading = true);

    try {
      final sel = '''
        id, ride_request_id, status, created_at, driver_id, driver_route_id,
        ride_requests (
          id, pickup_lat, pickup_lng, destination_lat, destination_lng,
          passenger_id, fare, seats, users ( id, name )
        )
      ''';

      final uid = user.id;
      final hasRoutes = _myRouteIds.isNotEmpty;
      final orExpr =
          hasRoutes
              ? 'driver_id.eq.$uid,driver_route_id.in.(${_myRouteIds.map((e) => '"$e"').join(',')})'
              : 'driver_id.eq.$uid';

      final raw = await _supabase
          .from('ride_matches')
          .select(sel)
          .or(orExpr)
          .order('created_at', ascending: false);

      final List<MatchCard> all = [];
      final List<String> rideIds = [];
      final Set<String> routeIds = {};

      for (final row in (raw as List)) {
        final m = (row as Map).cast<String, dynamic>();
        final req = (m['ride_requests'] as Map?)?.cast<String, dynamic>();

        // passenger
        String passengerName = 'Passenger';
        String? passengerId;
        final usersRel = req?['users'];
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
        passengerId ??= req?['passenger_id']?.toString();

        // seats requested
        final pax =
            (req?['seats'] as num?)?.toInt() ??
            (req?['passenger_count'] as num?)?.toInt() ??
            1;

        // reverse geocode best-effort
        String pickupAddr = 'Pickup';
        String destAddr = 'Destination';
        try {
          if (req?['pickup_lat'] != null && req?['pickup_lng'] != null) {
            final pm =
                (await placemarkFromCoordinates(
                  (req!['pickup_lat'] as num).toDouble(),
                  (req['pickup_lng'] as num).toDouble(),
                )).first;
            final s = [
              pm.thoroughfare,
              pm.subLocality,
              pm.locality,
            ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
            if (s.isNotEmpty) pickupAddr = s;
          }
          if (req?['destination_lat'] != null &&
              req?['destination_lng'] != null) {
            final pm =
                (await placemarkFromCoordinates(
                  (req!['destination_lat'] as num).toDouble(),
                  (req['destination_lng'] as num).toDouble(),
                )).first;
            final s = [
              pm.thoroughfare,
              pm.subLocality,
              pm.locality,
            ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
            if (s.isNotEmpty) destAddr = s;
          }
        } catch (_) {}

        final card = MatchCard(
          matchId: m['id'],
          rideRequestId: m['ride_request_id'],
          driverRouteId: m['driver_route_id']?.toString(),
          status: (m['status'] as String?)?.toLowerCase() ?? 'pending',
          createdAt: DateTime.parse(m['created_at']),
          passengerName: passengerName,
          passengerId: passengerId,
          pickupAddress: pickupAddr,
          destinationAddress: destAddr,
          fare: (req?['fare'] as num?)?.toDouble(),
          pax: pax,
          pickupLat: (req?['pickup_lat'] as num?)?.toDouble(),
          pickupLng: (req?['pickup_lng'] as num?)?.toDouble(),
          destLat: (req?['destination_lat'] as num?)?.toDouble(),
          destLng: (req?['destination_lng'] as num?)?.toDouble(),
        );

        all.add(card);
        if (card.driverRouteId != null) routeIds.add(card.driverRouteId!);
        rideIds.add(card.rideRequestId);
      }

      await _loadPaymentIntents(rideIds);
      await _loadRouteCapacities(routeIds.toList());

      // Group
      final updatedGroups = LinkedHashMap<String, RouteGroup>();
      for (final card in all) {
        final key = card.driverRouteId ?? 'unassigned';
        updatedGroups.putIfAbsent(
          key,
          () => RouteGroup(
            routeId: key,
            items: [],
            capacityTotal: _routeCapById[key]?['total'],
            capacityAvailable: _routeCapById[key]?['available'],
          ),
        );
        updatedGroups[key]!.items.add(card);
      }

      final declined = all.where((m) => m.status == 'declined').toList();
      final completed = all.where((m) => m.status == 'completed').toList();

      if (!mounted) return;
      setState(() {
        _routeGroups
          ..clear()
          ..addAll(updatedGroups);
        _declined = declined;
        _completed = completed;
        _loading = false;

        _badgeUpcoming =
            all
                .where((m) => m.status != 'declined' && m.status != 'completed')
                .length;
        _badgeDeclined = declined.length;
        _badgeCompleted = completed.length;
      });
    } catch (e) {
      if (!mounted) return;
      _d('_loadMatches error: $e');
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load matches failed: $e')));
    }
  }

  void _subscribeToRideMatches() {
    if (_matchChannel != null) return;

    _matchChannel =
        _supabase.channel('ride_matches_any_for_me')
          ..onPostgresChanges(
            schema: 'public',
            table: 'ride_matches',
            event: PostgresChangeEvent.insert,
            callback: (payload) {
              final rec = (payload.newRecord as Map?)?.cast<String, dynamic>();
              if (rec == null) return;

              final uid = _supabase.auth.currentUser?.id;
              final drvId = rec['driver_id']?.toString();
              final routeId = rec['driver_route_id']?.toString();

              final isMine =
                  (uid != null && drvId == uid) ||
                  (routeId != null && _myRouteIds.contains(routeId));
              if (!isMine) return;

              final id = rec['id']?.toString();
              if (id != null) {
                setState(() {
                  _newMatchIds.add(id);
                  _badgeUpcoming += 1;
                });
              }

              _showNotification(
                'New Request',
                'A passenger requested a pickup.',
              );
              _loadMatches();
            },
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'ride_matches',
            event: PostgresChangeEvent.update,
            callback: (_) => _loadMatches(),
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'ride_matches',
            event: PostgresChangeEvent.delete,
            callback: (_) => _loadMatches(),
          )
          ..subscribe();
  }

  /* ───────────── Capacities ───────────── */

  final Map<String, Map<String, int?>> _routeCapById = {};

  Future<void> _loadRouteCapacities(List<String> routeIds) async {
    _routeCapById.clear();
    if (routeIds.isEmpty) return;
    final res = await _supabase
        .from('driver_routes')
        .select('id, capacity_total, capacity_available')
        .inFilter('id', routeIds.toSet().toList());

    for (final row in (res as List)) {
      final m = (row as Map).cast<String, dynamic>();
      _routeCapById[m['id'] as String] = {
        'total': (m['capacity_total'] as num?)?.toInt(),
        'available': (m['capacity_available'] as num?)?.toInt(),
      };
    }
  }

  /* ───────────── Payments load ───────────── */

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

  /* ───────────── Per-match helpers ───────────── */

  Future<void> _acceptViaRpc(String matchId, String rideRequestId) async {
    await _supabase.rpc('accept_match', params: {'p_match_id': matchId});
    await _loadPaymentIntents([rideRequestId]);
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
    } catch (e) {
      _d('_syncPaymentForRide error: $e');
    } finally {
      await _loadPaymentIntents([rideRequestId]);
    }
  }

  Future<void> _updateMatchStatus(
    String matchId,
    String rideRequestId,
    String newStatus,
  ) async {
    await _supabase
        .from('ride_matches')
        .update({'status': newStatus})
        .eq('id', matchId);

    final upd = {'status': newStatus};
    await _supabase.from('ride_requests').update(upd).eq('id', rideRequestId);

    if (['completed', 'declined', 'canceled'].contains(newStatus)) {
      await _syncPaymentForRide(rideRequestId, newStatus);
    }
  }

  /* ───────────── Batch actions per route ───────────── */

  Future<void> _acceptSelectedForRoute(RouteGroup g) async {
    if (g.selected.isEmpty) return;

    setState(() => _loading = true);

    try {
      final capAvail = g.capacityAvailable ?? 0;

      // Sort selected pending by created_at (oldest first)
      final selectedPending =
          g.items
              .where(
                (m) => g.selected.contains(m.matchId) && m.status == 'pending',
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      int allowSeats = capAvail;
      int acceptedCount = 0;

      for (final m in selectedPending) {
        if (m.pax > allowSeats) continue;
        await _acceptViaRpc(m.matchId, m.rideRequestId);
        allowSeats -= m.pax;
        acceptedCount += 1;
        if (allowSeats <= 0) break;
      }

      if (acceptedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected riders exceed capacity.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accepted $acceptedCount rider(s).')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Accept failed: $e')));
    } finally {
      await _loadMatches();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startRoute(RouteGroup g) async {
    setState(() => _loading = true);
    try {
      final accepted = g.byStatus('accepted');
      for (final m in accepted) {
        await _updateMatchStatus(m.matchId, m.rideRequestId, 'en_route');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Started ${accepted.length} rider(s).')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Start failed: $e')));
    } finally {
      await _loadMatches();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeRoute(RouteGroup g) async {
    setState(() => _loading = true);
    try {
      final enroute = g.byStatus('en_route');
      for (final m in enroute) {
        await _updateMatchStatus(m.matchId, m.rideRequestId, 'completed');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completed ${enroute.length} rider(s).')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Complete failed: $e')));
    } finally {
      await _loadMatches();
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ───────────── UI helpers ───────────── */

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    setState(() {
      if (_tabController.index == 0) _badgeUpcoming = 0;
      if (_tabController.index == 1) _badgeDeclined = 0;
      if (_tabController.index == 2) _badgeCompleted = 0;
    });
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

  String _peso(num? v) =>
      v == null ? '₱0.00' : '₱${(v.toDouble()).toStringAsFixed(2)}';
  double? _driverNetForFare(num? fare) =>
      fare == null ? null : (fare.toDouble() * (1 - _platformFeeRate));

  Widget _miniIconBtn({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      iconSize: 20,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }

  Widget _pill(String text, {IconData? icon, Color? color}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (color ?? const Color(0xFFF2F2F7)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
      ),
    );
  }

  /* ───────────── Per-rider card (Declined/Completed tabs) ───────────── */

  Widget _buildFlatCard(MatchCard m) {
    final dt = DateFormat('MMM d, y • h:mm a').format(m.createdAt);
    final driverNet = _driverNetForFare(m.fare);
    final canOpenMap =
        m.status == 'accepted' ||
        m.status == 'en_route' ||
        m.status == 'completed';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black12.withOpacity(0.06)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.pickupAddress} → ${m.destinationAddress}',
              style: const TextStyle(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (m.hasCoords) ...[
              const SizedBox(height: 8),
              _MapThumb(
                pickup: m.pickup!,
                destination: m.destination!,
                onTap: () => _openMapPreview(single: m),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill('${m.pax} pax', icon: Icons.people),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.black54),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        m.passengerName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m.passengerId != null) ...[
                      const SizedBox(width: 6),
                      VerifiedBadge(userId: m.passengerId!, size: 16),
                      const SizedBox(width: 6),
                      UserRatingBadge(userId: m.passengerId!, iconSize: 14),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill(dt, icon: Icons.access_time),
                if (m.fare != null) _pill(_peso(m.fare), icon: Icons.payments),
                if (driverNet != null)
                  _pill(
                    'Driver net ${_peso(driverNet)}',
                    icon: Icons.account_balance_wallet,
                  ),
                if (_paymentByRide[m.rideRequestId] != null)
                  PaymentStatusChip(
                    status:
                        _paymentByRide[m.rideRequestId]?['status'] as String?,
                    amount:
                        _paymentByRide[m.rideRequestId]?['amount'] as double?,
                  ),
              ],
            ),
            const Divider(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  m.status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(m.status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _miniIconBtn(
                  icon: Icons.message_outlined,
                  tooltip: 'Open chat',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(matchId: m.matchId),
                      ),
                    );
                  },
                ),
                if (canOpenMap)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text(
                      'View ride',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(foregroundColor: _purple),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) =>
                                  DriverRideStatusPage(rideId: m.rideRequestId),
                        ),
                      );
                    },
                  ),
                if (m.status == 'completed' && m.passengerId != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.star),
                    label: const Text(
                      'Rate passenger',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(foregroundColor: _purple),
                    onPressed: () => _ratePassenger(m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /* ───────────── Grouped section per route (Upcoming tab) ───────────── */

  Widget _routeSection(RouteGroup g) {
    final pending = g.byStatus('pending');
    final accepted = g.byStatus('accepted');
    final enRoute = g.byStatus('en_route');

    final capText =
        (g.capacityTotal != null && g.capacityAvailable != null)
            ? 'Seats: ${g.capacityAvailable} / ${g.capacityTotal}'
            : 'Seats: n/a';

    List<Widget> _listFor(
      String label,
      List<MatchCard> list, {
      bool selectable = false,
    }) {
      if (list.isEmpty) return [];
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        ...list.map(
          (m) => Column(
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 12, right: 8),
                visualDensity: const VisualDensity(
                  horizontal: -2,
                  vertical: -2,
                ),
                value: selectable ? g.selected.contains(m.matchId) : false,
                onChanged:
                    selectable
                        ? (v) => setState(() {
                          if (v == true) {
                            g.selected.add(m.matchId);
                          } else {
                            g.selected.remove(m.matchId);
                          }
                        })
                        : null,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '${m.pickupAddress} → ${m.destinationAddress}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill('${m.pax} pax', icon: Icons.people),
                    if (m.fare != null)
                      _pill(_peso(m.fare), icon: Icons.payments),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person,
                          size: 14,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            m.passengerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (m.passengerId != null) ...[
                          const SizedBox(width: 6),
                          VerifiedBadge(userId: m.passengerId!, size: 16),
                          const SizedBox(width: 6),
                          UserRatingBadge(userId: m.passengerId!, iconSize: 14),
                        ],
                      ],
                    ),
                  ],
                ),
                secondary: SizedBox(
                  width: 100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniIconBtn(
                        icon: Icons.message_outlined,
                        tooltip: 'Chat',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(matchId: m.matchId),
                            ),
                          );
                        },
                      ),
                      if (m.status == 'pending')
                        _miniIconBtn(
                          icon: Icons.close,
                          tooltip: 'Decline',
                          onTap: () async {
                            setState(() => _loading = true);
                            try {
                              await _updateMatchStatus(
                                m.matchId,
                                m.rideRequestId,
                                'declined',
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Declined')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Decline failed: $e')),
                              );
                            } finally {
                              await _loadMatches();
                              if (mounted) setState(() => _loading = false);
                            }
                          },
                        ),
                      if (m.status == 'accepted' ||
                          m.status == 'en_route' ||
                          m.status == 'completed')
                        _miniIconBtn(
                          icon: Icons.map_outlined,
                          tooltip: 'View ride',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => DriverRideStatusPage(
                                      rideId: m.rideRequestId,
                                    ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              if (m.hasCoords)
                Padding(
                  padding: const EdgeInsets.fromLTRB(56, 0, 12, 10),
                  child: _MapThumb(
                    pickup: m.pickup!,
                    destination: m.destination!,
                    onTap: () => _openMapPreview(single: m, routeId: g.routeId),
                  ),
                ),
            ],
          ),
        ),
      ];
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black12.withOpacity(0.06)),
      ),
      color: Colors.white,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            Icon(Icons.alt_route, color: _purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                g.routeId == 'unassigned'
                    ? 'Unassigned route'
                    : 'Route ${g.routeId.substring(0, 8)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.02),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pill(capText, icon: Icons.event_seat),
              _pill('Pending: ${pending.length}', icon: Icons.hourglass_bottom),
              _pill('Accepted: ${accepted.length}', icon: Icons.check_circle),
              _pill('En route: ${enRoute.length}', icon: Icons.directions_car),
            ],
          ),
        ),
        children: [
          // Batch actions + route map
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Map: all pickups'),
                  style: OutlinedButton.styleFrom(foregroundColor: _purple),
                  onPressed:
                      g.items.any((m) => m.hasCoords)
                          ? () => _openMapPreview(group: g)
                          : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select all pending'),
                  style: OutlinedButton.styleFrom(foregroundColor: _purple),
                  onPressed:
                      pending.isEmpty
                          ? null
                          : () => setState(() {
                            for (final m in pending) {
                              g.selected.add(m.matchId);
                            }
                          }),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear selection'),
                  style: OutlinedButton.styleFrom(foregroundColor: _purple),
                  onPressed:
                      g.selected.isEmpty
                          ? null
                          : () => setState(() => g.selected.clear()),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: const Text('Accept selected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                      g.selected.isEmpty
                          ? null
                          : () => _acceptSelectedForRoute(g),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: accepted.isEmpty ? null : () => _startRoute(g),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Complete route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purpleDark,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: enRoute.isEmpty ? null : () => _completeRoute(g),
                ),
              ],
            ),
          ),
          const Divider(height: 12, thickness: 0.5),
          const SizedBox(height: 4),
          ..._listFor('Pending', pending, selectable: true),
          ..._listFor('Accepted', accepted, selectable: false),
          ..._listFor('En route', enRoute, selectable: false),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Future<void> _ratePassenger(MatchCard m) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || m.passengerId == null) return;

    final existing = await RatingsService(_supabase).getExistingRating(
      rideId: m.rideRequestId,
      raterUserId: uid,
      rateeUserId: m.passengerId!,
    );
    if (existing != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already rated this passenger.')),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => RateUserSheet(
            rideId: m.rideRequestId,
            raterUserId: uid,
            rateeUserId: m.passengerId!,
            rateeName: m.passengerName,
            rateeRole: 'passenger',
          ),
    );
  }

  /* ───────────── Map previews (single & group) ───────────── */

  Future<void> _openMapPreview({
    MatchCard? single,
    RouteGroup? group,
    String? routeId,
  }) async {
    assert(
      (single != null) ^ (group != null),
      'Pass exactly one of single or group',
    );

    // Try to overlay the driver route polyline if routeId (or group.routeId) exists
    List<LatLng> routePolylinePoints = [];
    final rid = routeId ?? group?.routeId;
    if (rid != null && rid != 'unassigned') {
      try {
        final row =
            await _supabase
                .from('driver_routes')
                .select('route_mode, route_polyline, manual_polyline')
                .eq('id', rid)
                .maybeSingle();

        if (row is Map) {
          String? encoded;
          final mode = row?['route_mode']?.toString();
          final routePolyline = row?['route_polyline']?.toString();
          final manualPolyline = row?['manual_polyline']?.toString();
          if (mode == 'manual') {
            encoded = manualPolyline ?? routePolyline;
          } else if (mode == 'osrm') {
            encoded = routePolyline ?? manualPolyline;
          } else {
            encoded = routePolyline ?? manualPolyline;
          }
          if (encoded != null && encoded.isNotEmpty) {
            final decoded = PolylinePoints().decodePolyline(encoded);
            routePolylinePoints =
                decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    // Prepare markers/lines
    final markers = <Marker>[];
    final extraLines = <Polyline>[];

    if (single != null && single.hasCoords) {
      final p = single.pickup!;
      final d = single.destination!;
      markers.addAll([
        Marker(
          point: p,
          width: 34,
          height: 34,
          child: const Icon(Icons.location_pin, color: _purple, size: 32),
        ),
        Marker(
          point: d,
          width: 30,
          height: 30,
          child: const Icon(Icons.flag, color: Colors.red, size: 26),
        ),
      ]);
      extraLines.add(
        Polyline(
          points: [p, d],
          strokeWidth: 3,
          color: _purpleDark.withOpacity(.85),
          isDotted: true,
        ),
      );
    } else if (group != null) {
      for (final m in group.items.where((x) => x.hasCoords)) {
        markers.add(
          Marker(
            point: m.pickup!,
            width: 30,
            height: 30,
            child: const Icon(
              Icons.person_pin_circle,
              color: _purple,
              size: 28,
            ),
          ),
        );
      }
    }

    final boundsPoints = <LatLng>[
      ...markers.map((m) => m.point),
      ...routePolylinePoints,
    ];
    if (boundsPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(boundsPoints);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => _LiveMapSheet(
            title:
                group != null ? 'All pickups on route' : 'Pickup & destination',
            bounds: bounds,
            staticMarkers: markers,
            routePolylinePoints: routePolylinePoints,
            extraPolylines: extraLines,
            purple: _purple,
          ),
    );
  }

  /* ───────────── Scaffold ───────────── */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withOpacity(0.4), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        backgroundColor: const Color.fromARGB(3, 0, 0, 0),
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.9),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: _purple,
                size: 18,
              ),
              onPressed: () => Navigator.maybePop(context),
              tooltip: 'Back',
            ),
          ),
        ),
        title: const Text(
          'Ride Matches',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          const _AdminMenuButton(),
          IconButton(
            icon: const Icon(Icons.verified_user),
            tooltip: 'Get Verified',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const VerifyIdentitySheet(role: 'driver'),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false, // evenly fills space
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A27F7), Color(0xFF4B18C9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF6A27F7).withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.black87,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                  tabs: [
                    _TabWithBadge(text: 'Upcoming', count: _badgeUpcoming),
                    _TabWithBadge(text: 'Declined', count: _badgeDeclined),
                    _TabWithBadge(text: 'Completed', count: _badgeCompleted),
                  ],
                ),
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
                  // UPCOMING: grouped by route
                  RefreshIndicator(
                    onRefresh: _loadMatches,
                    child:
                        _routeGroups.values.any(
                              (g) => g.items.any(
                                (m) =>
                                    m.status != 'declined' &&
                                    m.status != 'completed',
                              ),
                            )
                            ? ListView(
                              controller: _listScroll,
                              padding: const EdgeInsets.all(16),
                              children:
                                  _routeGroups.values
                                      .where(
                                        (g) => g.items.any(
                                          (m) =>
                                              m.status != 'declined' &&
                                              m.status != 'completed',
                                        ),
                                      )
                                      .map(_routeSection)
                                      .toList(),
                            )
                            : _emptyState('No upcoming matches yet'),
                  ),

                  // DECLINED
                  RefreshIndicator(
                    onRefresh: _loadMatches,
                    child:
                        _declined.isEmpty
                            ? _emptyState('No declined rides')
                            : ListView.builder(
                              controller: _listScroll,
                              padding: const EdgeInsets.all(16),
                              itemCount: _declined.length,
                              itemBuilder:
                                  (_, i) => _buildFlatCard(_declined[i]),
                            ),
                  ),

                  // COMPLETED
                  RefreshIndicator(
                    onRefresh: _loadMatches,
                    child:
                        _completed.isEmpty
                            ? _emptyState('No completed rides yet')
                            : ListView.builder(
                              controller: _listScroll,
                              padding: const EdgeInsets.all(16),
                              itemCount: _completed.length,
                              itemBuilder:
                                  (_, i) => _buildFlatCard(_completed[i]),
                            ),
                  ),
                ],
              ),
    );
  }

  Widget _emptyState(String message, {IconData icon = Icons.inbox}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: Colors.black26),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

/* ───────────── Small widgets ───────────── */

class _AdminMenuButton extends StatelessWidget {
  const _AdminMenuButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Admin',
      icon: const Icon(Icons.admin_panel_settings),
      onSelected: (value) {},
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

class _TabWithBadge extends StatelessWidget {
  const _TabWithBadge({required this.text, required this.count});
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          if (has) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade400, Colors.red.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ───────────── Map thumbnail widget ───────────── */

class _MapThumb extends StatelessWidget {
  const _MapThumb({
    required this.pickup,
    required this.destination,
    this.onTap,
  });

  final LatLng pickup;
  final LatLng destination;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bounds = LatLngBounds.fromPoints([pickup, destination]);
    const _purple = Color(0xFF6A27F7);
    const _purpleDark = Color(0xFF4B18C9);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 90,
            child: AbsorbPointer(
              absorbing: true,
              child: FlutterMap(
                options: MapOptions(
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  initialCenter: bounds.center,
                  initialZoom: 13,
                  bounds: bounds,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.godavao.app',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [pickup, destination],
                        strokeWidth: 3,
                        color: _purpleDark.withOpacity(.9),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pickup,
                        width: 24,
                        height: 24,
                        child: const Icon(
                          Icons.location_pin,
                          color: _purple,
                          size: 24,
                        ),
                      ),
                      Marker(
                        point: destination,
                        width: 22,
                        height: 22,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ───────────── Live Map Sheet (preview-only tracking) ───────────── */

class _LiveMapSheet extends StatefulWidget {
  const _LiveMapSheet({
    required this.title,
    required this.bounds,
    required this.staticMarkers,
    required this.routePolylinePoints,
    required this.extraPolylines,
    required this.purple,
  });

  final String title;
  final LatLngBounds bounds;
  final List<Marker> staticMarkers;
  final List<LatLng> routePolylinePoints;
  final List<Polyline> extraPolylines;
  final Color purple;

  @override
  State<_LiveMapSheet> createState() => _LiveMapSheetState();
}

class _LiveMapSheetState extends State<_LiveMapSheet> {
  final _mapController = MapController();
  StreamSubscription<Position>? _posSub;
  LatLng? _me;
  double? _acc; // meters
  DateTime? _ts;

  @override
  void initState() {
    super.initState();
    _startLivePreview();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _startLivePreview() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      // No permission: silent fail; static map still works
      return;
    }

    // Warm up: last known
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      setState(() {
        _me = LatLng(last.latitude, last.longitude);
        _acc = last.accuracy;
        _ts = DateTime.now();
      });
    }

    // Live stream (preview-friendly settings)
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 8, // meters
      ),
    ).listen((pos) {
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _acc = pos.accuracy;
        _ts = DateTime.now();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final basePolylines = <Polyline>[
      if (widget.routePolylinePoints.isNotEmpty)
        Polyline(
          points: widget.routePolylinePoints,
          strokeWidth: 4,
          color: widget.purple.withOpacity(0.85),
        ),
      ...widget.extraPolylines,
    ];

    final allMarkers = <Marker>[
      ...widget.staticMarkers,
      if (_me != null)
        Marker(
          point: _me!,
          width: 36,
          height: 36,
          child: const Icon(Icons.my_location, size: 28, color: Colors.blue),
        ),
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.bounds.center,
                initialZoom: 13,
                bounds: widget.bounds,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.godavao.app',
                ),
                if (basePolylines.isNotEmpty)
                  PolylineLayer(polylines: basePolylines),
                if (allMarkers.isNotEmpty) MarkerLayer(markers: allMarkers),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.route,
                              size: 16,
                              color: Colors.purple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.title,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Center on me
            Positioned(
              right: 12,
              bottom: 72,
              child: FloatingActionButton.small(
                heroTag: 'centerOnMe',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed:
                    _me == null ? null : () => _mapController.move(_me!, 16),
                child: const Icon(Icons.my_location),
              ),
            ),

            // GPS status pill
            if (_me != null)
              Positioned(
                left: 12,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.gps_fixed,
                        size: 14,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _acc != null
                            ? '±${_acc!.toStringAsFixed(0)} m • ${_ago(_ts)}'
                            : 'Live',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

            // Close
            Positioned(
              right: 12,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'closeMapSheet',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime? t) {
    if (t == null) return '';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return '${s}s ago';
    final m = (s / 60).floor();
    return '${m}m ago';
  }
}
