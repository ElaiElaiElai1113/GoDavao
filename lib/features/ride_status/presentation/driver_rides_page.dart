// lib/features/ride_status/presentation/driver_rides_page.dart
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:godavao/common/empty_state.dart';
import 'package:godavao/features/ratings/presentation/rating_details_sheet.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';

// ⭐ these 3 are important for ratings
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';

import 'package:godavao/features/payments/presentation/payment_status_chip.dart';
import 'package:godavao/features/ride_status/presentation/driver_ride_status_page.dart';
import 'package:godavao/features/ride_status/models/match_card_model.dart';
import 'package:godavao/features/ride_status/models/route_group_model.dart';
import 'package:godavao/core/shared_fare_service.dart';
import 'package:godavao/features/live_tracking/data/live_subscriber.dart';
import 'package:godavao/main.dart' show localNotify;

/* ────────────────────────────────────────────────────────────────────────── */

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({super.key});
  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final _sharedFareService = SharedFareService(client: _supabase);

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  static const bool _dbg = false;
  void _d(Object? msg) {
    if (_dbg) debugPrint('[DriverRides] $msg');
  }

  // ⭐ Ratings cache: user_id -> {avg, count}
  final Map<String, Map<String, dynamic>> _ratingCache = {};
  static const double _defaultNewRating = 3.0;

  Future<void> _hydratePassengerRatings(Iterable<String> passengerIds) async {
    final ids = passengerIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    final svc = RatingsService(_supabase);

    final futures = <Future<void>>[];
    for (final uid in ids) {
      if (_ratingCache.containsKey(uid)) continue;
      futures.add(
        svc
            .fetchUserAggregate(uid)
            .then((agg) {
              _ratingCache[uid] = {
                'avg': (agg['avg_rating'] as num?)?.toDouble(),
                'count': (agg['rating_count'] as num?)?.toInt() ?? 0,
              };
            })
            .catchError((_) {
              _ratingCache[uid] = {'avg': null, 'count': 0};
            }),
      );
    }
    await Future.wait(futures);
  }

  Widget _ratingChip(double? avg, int? count) {
    final isNew = (count == null || count == 0);
    final shown = (isNew ? _defaultNewRating : (avg ?? _defaultNewRating));
    final label =
        isNew
            ? '${shown.toStringAsFixed(1)} (new)'
            : '${shown.toStringAsFixed(1)} ($count)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  late final TabController _tabController;
  final _listScroll = ScrollController();

  // Buckets (for Declined/Completed tabs)
  List<MatchCard> _declined = [];
  List<MatchCard> _completed = [];

  // Grouped (pending | accepted | en_route) by route
  final LinkedHashMap<String, RouteGroup> _routeGroups = LinkedHashMap();

  // My authored routes
  final Set<String> _myRouteIds = {};

  // New badges
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);

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
        if (!mounted) return;
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
                if (!mounted) return;
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
                if (!mounted) return;
                setState(() => _platformFeeRate = rate);
              }
            },
          )
          ..subscribe();
  }

  double? _parseFeeRate(Map<dynamic, dynamic>? row) {
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
        id, ride_request_id, status, created_at, driver_id, driver_route_id, seats_allocated, driver_routes ( id, name ),
        ride_requests ( id, pickup_lat, pickup_lng, destination_lat, destination_lng, passenger_id, fare, requested_seats, users ( id, name ), status )
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
        final routeRel = (m['driver_routes'] as Map?)?.cast<String, dynamic>();
        final routeName = routeRel?['name']?.toString();

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

        // seats
        final seatsAllocated = (m['seats_allocated'] as num?)?.toInt();
        final reqSeats =
            (req?['requested_seats'] as num?)?.toInt() ??
            (req?['seats'] as num?)?.toInt();
        final pax = (seatsAllocated ?? reqSeats ?? 1);

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
          driverRouteName: routeName,
          matchId: m['id'].toString(),
          rideRequestId: m['ride_request_id'].toString(),
          driverRouteId: m['driver_route_id']?.toString(),
          status: (m['status'] as String?)?.toLowerCase() ?? 'pending',
          createdAt: DateTime.parse(m['created_at'].toString()),
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

      // ⭐ Ratings hydration + attach to cards
      final passengerIds = all.map((m) => m.passengerId).whereType<String>();
      await _hydratePassengerRatings(passengerIds);

      final List<MatchCard> allWithRatings =
          all.map((m) {
            double? avg;
            int? cnt;

            if (m.passengerId != null &&
                _ratingCache.containsKey(m.passengerId)) {
              final r = _ratingCache[m.passengerId!]!;
              avg = (r['avg'] as num?)?.toDouble();
              cnt = (r['count'] as num?)?.toInt() ?? 0;
            } else {
              avg = null;
              cnt = 0;
            }

            return MatchCard(
              matchId: m.matchId,
              rideRequestId: m.rideRequestId,
              driverRouteId: m.driverRouteId,
              status: m.status,
              createdAt: m.createdAt,
              passengerName: m.passengerName,
              passengerId: m.passengerId,
              pickupAddress: m.pickupAddress,
              destinationAddress: m.destinationAddress,
              fare: m.fare,
              pax: m.pax,
              pickupLat: m.pickupLat,
              pickupLng: m.pickupLng,
              destLat: m.destLat,
              destLng: m.destLng,
              driverRouteName: m.driverRouteName,
              ratingAvg: avg,
              ratingCount: cnt,
            );
          }).toList();

      await _loadPaymentIntents(rideIds);
      await _loadRouteCapacities(routeIds.toList());

      // Group
      final updatedGroups = <String, RouteGroup>{};
      for (final card in allWithRatings) {
        final key = card.driverRouteId ?? 'unassigned';
        if (!updatedGroups.containsKey(key)) {
          updatedGroups[key] = RouteGroup(
            routeId: key,
            items: [],
            capacityTotal: _routeCapById[key]?['total'],
            capacityAvailable: _routeCapById[key]?['available'],
          );
        }
        updatedGroups[key] = updatedGroups[key]!.addMatch(card);
      }

      final declined =
          allWithRatings.where((m) => m.status == 'declined').toList();
      final completed =
          allWithRatings.where((m) => m.status == 'completed').toList();

      if (!mounted) return;
      setState(() {
        _routeGroups
          ..clear()
          ..addAll(updatedGroups);
        _declined = declined;
        _completed = completed;
        _loading = false;

        _badgeUpcoming =
            allWithRatings
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
                if (mounted) {
                  setState(() {
                    _newMatchIds.add(id);
                    _badgeUpcoming += 1;
                  });
                }
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
    await _supabase.rpc<void>('accept_match', params: {'p_match_id': matchId});
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
    await _supabase
        .from('ride_requests')
        .update({'status': newStatus})
        .eq('id', rideRequestId);

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

      // Recalculate fares using distance-proportional pricing for all passengers on this route
      if (acceptedCount > 0 && g.routeId.isNotEmpty) {
        try {
          await _sharedFareService.calculateAndStoreSharedFares(g.routeId);
          _d('Recalculated shared fares for route ${g.routeId}');
        } catch (e) {
          // Log but don't fail the acceptance if fare calculation fails
          _d('Warning: Failed to recalculate shared fares: $e');
        }
      }

      if (!mounted) return;
      if (acceptedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected riders exceed capacity.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accepted $acceptedCount rider(s). Fares updated based on distance.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Accept failed: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Started ${accepted.length} rider(s).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Start failed: $e')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Completed ${enroute.length} rider(s).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Complete failed: $e')));
      }
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

  Widget _pill(String text, {IconData? icon, Color? color}) {
    final baseColor = color ?? _purple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: baseColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: baseColor.withValues(alpha: 0.95)),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: baseColor.withValues(alpha: 0.95),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /* ───────────── Per-rider FLAT card (Declined/Completed tabs) ───────────── */

  Widget _buildFlatCard(MatchCard m) {
    final dt = DateFormat('MMM d, y • h:mm a').format(m.createdAt);
    final driverNet = _driverNetForFare(m.fare);
    final canOpenMap =
        m.status == 'accepted' ||
        m.status == 'en_route' ||
        m.status == 'completed';
    final pr = _paymentByRide[m.rideRequestId];

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black12.withValues(alpha: 0.06)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.pickupAddress} → ${m.destinationAddress}',
              style: const TextStyle(fontWeight: FontWeight.w800),
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill('${m.pax} pax', icon: Icons.people_alt),
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (m.passengerId != null) ...[
                      const SizedBox(width: 6),
                      VerifiedBadge(userId: m.passengerId!, size: 16),
                      const SizedBox(width: 6),
                      UserRatingBadge(userId: m.passengerId!, iconSize: 14),
                    ],
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(18),
                            ),
                          ),
                          builder:
                              (_) => RatingDetailsSheet(
                                userId: m.passengerId!,
                                title: 'Passenger feedback',
                              ),
                        );
                      },
                      child: _ratingChip(m.ratingAvg, m.ratingCount),
                    ),
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
                if (pr != null)
                  PaymentStatusChip(
                    status: pr['status'] as String?,
                    amount: (pr['amount'] as num?)?.toDouble(),
                  ),
              ],
            ),
            const Divider(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _pill(m.status.toUpperCase(), color: _statusColor(m.status)),
                IconButton(
                  tooltip: 'Open chat',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ChatPage(matchId: m.matchId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.message_outlined),
                ),
                if (canOpenMap)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text(
                      'View ride',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _ratePassenger(m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /* ───────────── Helpers for immutable RouteGroup updates ───────────── */

  void _updateRouteGroup(String routeId, RouteGroup updated) {
    setState(() {
      _routeGroups[routeId] = updated;
    });
  }

  void _toggleMatchSelection(String routeId, String matchId) {
    final current = _routeGroups[routeId];
    if (current != null) {
      _updateRouteGroup(routeId, current.toggleSelection(matchId));
    }
  }

  void _clearRouteSelection(String routeId) {
    final current = _routeGroups[routeId];
    if (current != null) {
      _updateRouteGroup(routeId, current.clearSelection());
    }
  }

  void _selectAllPendingForRoute(String routeId) {
    final current = _routeGroups[routeId];
    if (current != null) {
      var updated = current.clearSelection();
      for (final m in current.pending) {
        updated = updated.toggleSelection(m.matchId);
      }
      _updateRouteGroup(routeId, updated);
    }
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

    List<Widget> listFor(
      String label,
      List<MatchCard> list, {
      bool selectable = false,
    }) {
      if (list.isEmpty) return [];
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: _purpleDark,
            ),
          ),
        ),
        ...list.map((m) {
          final canOpenRide =
              m.status == 'accepted' ||
              m.status == 'en_route' ||
              m.status == 'completed';
          final isSelected = g.selected.contains(m.matchId);
          return _MatchListTile(
            m: m,
            selectable: selectable,
            selected: selectable ? isSelected : false,
            onSelect:
                selectable
                    ? (v) => _toggleMatchSelection(g.routeId, m.matchId)
                    : (_) {},
            onDecline: () async {
              setState(() => _loading = true);
              try {
                await _updateMatchStatus(
                  m.matchId,
                  m.rideRequestId,
                  'declined',
                );
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Declined')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Decline failed: $e')));
                }
              } finally {
                await _loadMatches();
                if (mounted) setState(() => _loading = false);
              }
            },
            onOpenRide:
                canOpenRide
                    ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder:
                              (_) =>
                                  DriverRideStatusPage(rideId: m.rideRequestId),
                        ),
                      );
                    }
                    : null,
            onChat: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => ChatPage(matchId: m.matchId)),
              );
            },
            buildPill:
                (text, {icon, color}) => _pill(text, icon: icon, color: color),
            buildRatingChip: (avg, count) => _ratingChip(avg, count),
            mapThumb:
                m.hasCoords
                    ? _MapThumb(
                      pickup: m.pickup!,
                      destination: m.destination!,
                      onTap:
                          () => _openMapPreview(
                            single: m,
                            routeGroupId: g.routeId,
                          ),
                    )
                    : const SizedBox.shrink(),
            trailingStatusColor: _statusColor(m.status),
            onTapRating:
                m.passengerId == null
                    ? null
                    : () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                        ),
                        builder:
                            (_) => RatingDetailsSheet(
                              userId: m.passengerId!,
                              title: 'Passenger feedback',
                            ),
                      );
                    },
          );
        }),
      ];
    }

    final routeTitle =
        g.routeId == 'unassigned'
            ? 'Unassigned route'
            : (g.items.isNotEmpty && g.items.first.driverRouteName != null
                ? g.items.first.driverRouteName!
                : 'Route ${g.routeId.substring(0, 8)}');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.8),
            Colors.white.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          collapsedBackgroundColor: Colors.white.withValues(alpha: 0.9),
          backgroundColor: Colors.white,
          leading: const Icon(Icons.alt_route, color: _purple),
          title: Text(
            routeTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: _purpleDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill(capText, icon: Icons.event_seat),
                _pill(
                  'Pending: ${pending.length}',
                  icon: Icons.hourglass_bottom,
                ),
                _pill('Accepted: ${accepted.length}', icon: Icons.check_circle),
                _pill(
                  'En route: ${enRoute.length}',
                  icon: Icons.directions_car,
                ),
              ],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text('Map: all pickups'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        g.items.any((m) => m.hasCoords)
                            ? () => _openMapPreview(group: g)
                            : null,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.select_all),
                    label: const Text('Select all pending'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        pending.isEmpty
                            ? null
                            : () => _selectAllPendingForRoute(g.routeId),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear selection'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        g.selected.isEmpty
                            ? null
                            : () => _clearRouteSelection(g.routeId),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.done_all),
                    label: const Text('Accept selected'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    onPressed: accepted.isEmpty ? null : () => _startRoute(g),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Complete route'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purpleDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    onPressed: enRoute.isEmpty ? null : () => _completeRoute(g),
                  ),
                ],
              ),
            ),
            const Divider(height: 12, thickness: 0.5),
            const SizedBox(height: 4),
            ...listFor('Pending', pending, selectable: true),
            ...listFor('Accepted', accepted, selectable: false),
            ...listFor('En route', enRoute, selectable: false),
            const SizedBox(height: 10),
          ],
        ),
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
    await showModalBottomSheet<void>(
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
    String? routeGroupId,
  }) async {
    assert(
      (single != null) ^ (group != null),
      'Pass exactly one of single or group',
    );

    // 1) Overlay the driver route polyline if route exists
    List<LatLng> routePolylinePoints = [];
    final rid = routeGroupId ?? group?.routeId;
    if (rid != null && rid != 'unassigned') {
      try {
        final row =
            await _supabase
                .from('driver_routes')
                .select('route_mode, route_polyline, manual_polyline')
                .eq('id', rid)
                .maybeSingle();

        if (row is Map) {
          final mode = row?['route_mode']?.toString();
          final routePolyline = row?['route_polyline']?.toString();
          final manualPolyline = row?['manual_polyline']?.toString();

          String? encoded = switch (mode) {
            'manual' => (manualPolyline ?? routePolyline),
            'osrm' => (routePolyline ?? manualPolyline),
            _ => (routePolyline ?? manualPolyline),
          };

          if (encoded != null && encoded.isNotEmpty) {
            final decoded = PolylinePoints().decodePolyline(encoded);
            routePolylinePoints =
                decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    // 2) Prepare markers/lines + legend chips
    final markers = <Marker>[];
    final extraLines = <Polyline>[];
    final legendChips = <Widget>[];

    if (single != null && single.hasCoords) {
      // —— Single rider preview
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
          color: _purpleDark.withValues(alpha: .85),
          isDotted: true,
        ),
      );

      legendChips.add(
        _legendChipLocal(
          _purple,
          '${single.passengerName} • ${single.pickupAddress} → ${single.destinationAddress}',
        ),
      );

      final boundsPoints = <LatLng>[
        ...markers.map((m) => m.point),
        ...routePolylinePoints,
      ];
      if (boundsPoints.isEmpty) return;
      final bounds = LatLngBounds.fromPoints(boundsPoints);

      final allowPassengerLive = single.status == 'en_route';

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder:
            (_) => _LiveMapSheet(
              title: 'Pickup & destination',
              bounds: bounds,
              staticMarkers: markers,
              routePolylinePoints: routePolylinePoints,
              extraPolylines: extraLines,
              purple: _purple,
              legendChips: legendChips,
              rideIdForPassengerLive: single.rideRequestId,
              allowPassengerLive: allowPassengerLive,
            ),
      );
      return;
    } else if (group != null) {
      // —— Group preview: ONLY accepted + en_route riders (no live dots here)
      final riders =
          group.items
              .where(
                (m) =>
                    m.hasCoords &&
                    (m.status == 'accepted' || m.status == 'en_route'),
              )
              .toList();

      Color colorAt(int i) {
        const palette = <Color>[
          Color(0xFFE53935),
          Color(0xFF1E88E5),
          Color(0xFF43A047),
          Color(0xFFF4511E),
          Color(0xFF6D4C41),
          Color(0xFF8E24AA),
          Color(0xFF00897B),
          Color(0xFFFDD835),
        ];
        return palette[i % palette.length];
      }

      Icon _pin(IconData icon, Color color, {double size = 28}) =>
          Icon(icon, color: color, size: size);

      for (int i = 0; i < riders.length; i++) {
        final m = riders[i];
        final color = colorAt(i);
        markers.addAll([
          Marker(
            point: m.pickup!,
            width: 30,
            height: 30,
            child: _pin(Icons.location_pin, color),
          ),
          Marker(
            point: m.destination!,
            width: 28,
            height: 28,
            child: _pin(Icons.flag, color),
          ),
        ]);
        extraLines.add(
          Polyline(
            points: [m.pickup!, m.destination!],
            strokeWidth: 3,
            color: color,
            isDotted: true,
          ),
        );
        legendChips.add(_legendChipLocal(color, m.passengerName));
      }

      final boundsPoints = <LatLng>[
        ...markers.map((m) => m.point),
        ...routePolylinePoints,
      ];
      if (boundsPoints.isEmpty) return;
      final bounds = LatLngBounds.fromPoints(boundsPoints);

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder:
            (_) => _LiveMapSheet(
              title: 'All pickups on route',
              bounds: bounds,
              staticMarkers: markers,
              routePolylinePoints: routePolylinePoints,
              extraPolylines: extraLines,
              purple: _purple,
              legendChips: legendChips,
              rideIdForPassengerLive: null,
              allowPassengerLive: false,
            ),
      );
      return;
    }
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
              colors: [_purple.withValues(alpha: 0.4), Colors.transparent],
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
            backgroundColor: Colors.white.withValues(alpha: 0.9),
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
              showModalBottomSheet<void>(
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
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_purple, _purpleDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _purple.withValues(alpha: 0.25),
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
                  // UPCOMING
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
        padding: const EdgeInsets.all(24),
        child: EmptyStateCard(
          icon: icon,
          title: message,
          subtitle: 'Check back later for updates.',
        ),
      ),
    );
  }

  // Small local legend chip for map sheets
  Widget _legendChipLocal(Color c, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────── Small widgets ───────────────────────── */

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
                    color: Colors.red.withValues(alpha: 0.35),
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

/* ───────────────────────── Map thumbnail widget ───────────────────────── */

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
    const purple = Color(0xFF6A27F7);
    const purpleDark = Color(0xFF4B18C9);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 96,
            child: AbsorbPointer(
              absorbing: true,
              child: FlutterMap(
                options: MapOptions(
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  initialCenter: bounds.center,
                  initialZoom: 13,
                  initialCameraFit: CameraFit.bounds(bounds: bounds),
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
                        color: purpleDark.withValues(alpha: .9),
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
                          color: purple,
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

/* ───────────────────────── Live Map Sheet ───────────────────────── */

class _LiveMapSheet extends StatefulWidget {
  const _LiveMapSheet({
    required this.title,
    required this.bounds,
    required this.staticMarkers,
    required this.routePolylinePoints,
    required this.extraPolylines,
    required this.purple,
    this.legendChips = const [],
    this.rideIdForPassengerLive,
    this.allowPassengerLive = false,
  });

  final String title;
  final LatLngBounds bounds;
  final List<Marker> staticMarkers;
  final List<LatLng> routePolylinePoints;
  final List<Polyline> extraPolylines;
  final Color purple;
  final List<Widget> legendChips;

  /// If provided and [allowPassengerLive] is true, we subscribe to passenger live.
  final String? rideIdForPassengerLive;
  final bool allowPassengerLive;

  @override
  State<_LiveMapSheet> createState() => _LiveMapSheetState();
}

class _LiveMapSheetState extends State<_LiveMapSheet> {
  final _mapController = MapController();

  // Device preview live (optional)
  StreamSubscription<Position>? _posSub;
  LatLng? _me;
  double? _acc; // meters
  DateTime? _ts;

  // Passenger live (privacy-aware)
  LiveSubscriber? _paxLive;
  LatLng? _pax;
  DateTime? _paxTs;

  @override
  void initState() {
    super.initState();
    _startDevicePreview();
    _maybeStartPassengerLive();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _paxLive?.dispose();
    super.dispose();
  }

  Future<void> _startDevicePreview() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      if (!mounted) return;
      setState(() {
        _me = LatLng(last.latitude, last.longitude);
        _acc = last.accuracy;
        _ts = DateTime.now();
      });
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 8,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _acc = pos.accuracy;
        _ts = DateTime.now();
      });
    });
  }

  void _maybeStartPassengerLive() {
    if (!widget.allowPassengerLive || widget.rideIdForPassengerLive == null)
      return;

    _paxLive = LiveSubscriber(
      Supabase.instance.client,
      rideId: widget.rideIdForPassengerLive!,
      actor: 'passenger',
      onUpdate: (pos, heading) {
        if (!mounted) return;
        setState(() {
          _pax = pos;
          _paxTs = DateTime.now();
        });
      },
    )..listen();
  }

  @override
  Widget build(BuildContext context) {
    final basePolylines = <Polyline>[
      if (widget.routePolylinePoints.isNotEmpty)
        Polyline(
          points: widget.routePolylinePoints,
          strokeWidth: 4,
          color: widget.purple.withValues(alpha: 0.9),
        ),
      ...widget.extraPolylines,
    ];

    final allMarkers = <Marker>[
      ...widget.staticMarkers,
      if (_pax != null && widget.allowPassengerLive)
        Marker(
          point: _pax!,
          width: 34,
          height: 34,
          child: const Icon(
            Icons.person_pin_circle,
            size: 30,
            color: Colors.deepPurple,
          ),
        ),
      if (_me != null)
        Marker(
          point: _me!,
          width: 32,
          height: 32,
          child: const Icon(Icons.my_location, size: 26, color: Colors.blue),
        ),
    ];

    final legend = <Widget>[
      ...widget.legendChips,
      if (_pax != null && widget.allowPassengerLive)
        _legendChipLocal(Colors.deepPurple, 'Passenger (live)'),
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
                initialCameraFit: CameraFit.bounds(bounds: widget.bounds),
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
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.route, size: 16, color: Colors.purple),
                            SizedBox(width: 6),
                            Text('Live Map', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (legend.isNotEmpty)
              Positioned(
                left: 8,
                top: 60,
                right: 8,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Wrap(spacing: 6, runSpacing: 6, children: legend),
                  ),
                ),
              ),

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

            Positioned(
              left: 12,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.black12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.allowPassengerLive && _paxTs != null) ...[
                      const Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pax ${_ago(_paxTs)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ] else if (_me != null) ...[
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
                    ] else ...[
                      const Text('Map preview', style: TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),

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

  Widget _legendChipLocal(Color c, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────── Modern, flexible list tile ───────────────────────── */

class _MatchListTile extends StatelessWidget {
  const _MatchListTile({
    required this.m,
    required this.selectable,
    required this.selected,
    required this.onSelect,
    required this.onDecline,
    required this.onOpenRide,
    required this.onChat,
    required this.buildPill,
    required this.buildRatingChip,
    required this.mapThumb,
    required this.trailingStatusColor,
    this.onTapRating,
  });

  final MatchCard m;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool?> onSelect;
  final VoidCallback onDecline;
  final VoidCallback? onOpenRide;
  final VoidCallback onChat;

  final Widget Function(String text, {IconData? icon, Color? color}) buildPill;
  final Widget Function(double? avg, int? count) buildRatingChip;
  final Widget mapThumb;

  final Color trailingStatusColor;
  final VoidCallback? onTapRating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOpenMap = onOpenRide != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 28,
                  child: Checkbox(
                    visualDensity: const VisualDensity(
                      horizontal: -3,
                      vertical: -3,
                    ),
                    value: selected,
                    onChanged: onSelect,
                  ),
                ),
              )
            else
              const SizedBox(width: 4),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m.pickupAddress} → ${m.destinationAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      buildPill('${m.pax} pax', icon: Icons.people_alt),
                      if (m.fare != null)
                        buildPill(_pesoStatic(m.fare), icon: Icons.payments),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.black54,
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              m.passengerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (m.passengerId != null) ...[
                            VerifiedBadge(userId: m.passengerId!, size: 16),
                            UserRatingBadge(
                              userId: m.passengerId!,
                              iconSize: 14,
                            ),
                          ],
                          GestureDetector(
                            onTap: onTapRating,
                            child: buildRatingChip(m.ratingAvg, m.ratingCount),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (m.hasCoords) ...[const SizedBox(height: 8), mapThumb],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Trailing column
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: trailingStatusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: trailingStatusColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    m.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: trailingStatusColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Chat',
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onPressed: onChat,
                      icon: const Icon(Icons.message_outlined),
                    ),
                    if (m.status == 'pending')
                      IconButton(
                        tooltip: 'Decline',
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: onDecline,
                        icon: const Icon(Icons.close),
                      ),
                    if (canOpenMap)
                      IconButton(
                        tooltip: 'View ride',
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        onPressed: onOpenRide,
                        icon: const Icon(Icons.map_outlined),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _pesoStatic(num? v) =>
      v == null ? '₱0.00' : '₱${(v.toDouble()).toStringAsFixed(2)}';
}
