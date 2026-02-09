import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/common/app_colors.dart';

import 'package:godavao/common/error_state.dart';
import 'package:godavao/common/empty_state.dart';
import 'package:godavao/core/reverse_geocoder.dart';
import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/features/maps/passenger_map_page.dart';
import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';

class PassengerMyRidesPage extends StatefulWidget {
  const PassengerMyRidesPage({super.key});
  @override
  State<PassengerMyRidesPage> createState() => _PassengerMyRidesPageState();
}

class _PassengerMyRidesPageState extends State<PassengerMyRidesPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  bool _working = false;
  String? _error;

  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _history = [];

  StreamSubscription<List<Map<String, dynamic>>>? _rideReqSub;
  StreamSubscription<List<Map<String, dynamic>>>? _rideMatchSub;

  final Map<String, String> _addr = {};
  final Set<String> _ratedRideIds = {};
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _upcomingFilter = 'all';
  String _historyFilter = 'all';

  static const _purple = AppColors.purple;
  static const _purpleDark = AppColors.purpleDark;
  static const _bg = AppColors.bg;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _rideReqSub?.cancel();
    _rideMatchSub?.cancel();
    _search.dispose();
    super.dispose();
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

    try {
      final rows = await sb.rpc<List<Map<String, dynamic>>>('passenger_rides_for_user').select();
      final list =
          (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _applyRidesToState(list);
      await _refreshRatedFlagsForCompleted(list);
      _backfillAddresses(list);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load rides.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    _rideReqSub?.cancel();
    _rideReqSub = sb
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('passenger_id', me.id)
        .listen((rows) async {
          final ids =
              rows
                  .map((r) => r['id'])
                  .where((id) => id != null)
                  .cast<String>()
                  .toList();
          if (ids.isNotEmpty) await _refreshRides(ids);
        });

    _rideMatchSub?.cancel();
    _rideMatchSub = sb.from('ride_matches').stream(primaryKey: ['id']).listen((
      rows,
    ) async {
      final rideIds =
          rows
              .map((r) => r['ride_request_id'])
              .where((id) => id != null)
              .cast<String>()
              .toSet()
              .toList();
      if (rideIds.isNotEmpty) await _refreshRides(rideIds);
    });
  }

  Future<void> _refreshRides(List<String> rideIds) async {
    try {
      final rows = await sb
          .from('v_passenger_ride_status')
          .select('''
            id, effective_status, created_at, fare,
            pickup_lat, pickup_lng, destination_lat, destination_lng,
            passenger_id, driver_id, driver_name
          ''')
          .inFilter('id', rideIds);

      final list =
          (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      _applyRidesToState(list);
      await _refreshRatedFlagsForCompleted(list);
      _backfillAddresses(list);
    } catch (_) {}
  }

  void _applyRidesToState(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final ad =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.now();
      final bd =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.now();
      return bd.compareTo(ad);
    });

    const up = ['pending', 'accepted', 'en_route'];
    const hist = ['completed', 'declined', 'canceled', 'cancelled'];

    final upcoming = <Map<String, dynamic>>[];
    final history = <Map<String, dynamic>>[];

    for (final r in rows) {
      final s = (r['effective_status'] as String?)?.toLowerCase() ?? '';
      if (up.contains(s)) {
        upcoming.add(r);
      } else if (hist.contains(s)) {
        history.add(r);
      } else {
        history.add(r);
      }
    }

    if (!mounted) return;
    setState(() {
      _upcoming = _mergeWithExisting(_upcoming, upcoming);
      _history = _mergeWithExisting(_history, history);
    });
  }

  List<Map<String, dynamic>> _mergeWithExisting(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> incoming,
  ) {
    final byId = {for (final e in existing) e['id'].toString(): e};
    for (final inc in incoming) {
      final id = inc['id'].toString();
      if (byId.containsKey(id)) {
        byId[id] = {...byId[id]!, ...inc};
      } else {
        byId[id] = inc;
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      final ad =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.now();
      final bd =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.now();
      return bd.compareTo(ad);
    });
    return list;
  }

  List<Map<String, dynamic>> _filterRides(
    List<Map<String, dynamic>> list, {
    required bool upcoming,
  }) {
    final q = _query.trim().toLowerCase();
    final filter = upcoming ? _upcomingFilter : _historyFilter;
    final out =
        list.where((r) {
          final status =
              (r['effective_status'] as String? ?? '').toLowerCase();
          final normalized =
              (status == 'canceled' || status == 'cancelled' || status == 'declined')
                  ? 'canceled'
                  : status;

          if (filter != 'all' && normalized != filter) return false;
          if (q.isEmpty) return true;

          final haystack = [
            r['driver_name']?.toString(),
            r['pickup_address']?.toString(),
            r['destination_address']?.toString(),
          ].whereType<String>().join(' ').toLowerCase();
          return haystack.contains(q);
        }).toList();
    return out;
  }

  void _backfillAddresses(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      _fillAddressForRide(r);
    }
  }

  Future<void> _fillAddressForRide(Map<String, dynamic> r) async {
    final pLat = (r['pickup_lat'] as num?)?.toDouble();
    final pLng = (r['pickup_lng'] as num?)?.toDouble();
    final dLat = (r['destination_lat'] as num?)?.toDouble();
    final dLng = (r['destination_lng'] as num?)?.toDouble();
    if (pLat == null || pLng == null || dLat == null || dLng == null) return;

    final pickupAddr = await _safeReverse(pLat, pLng);
    final destAddr = await _safeReverse(dLat, dLng);

    if (!mounted) return;
    setState(() {
      _upcoming =
          _upcoming.map((ride) {
            if (ride['id'] == r['id']) {
              return {
                ...ride,
                'pickup_address': pickupAddr,
                'destination_address': destAddr,
              };
            }
            return ride;
          }).toList();
      _history =
          _history.map((ride) {
            if (ride['id'] == r['id']) {
              return {
                ...ride,
                'pickup_address': pickupAddr,
                'destination_address': destAddr,
              };
            }
            return ride;
          }).toList();
    });
  }

  Future<String> _safeReverse(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    if (_addr.containsKey(key)) return _addr[key]!;
    final label = await reverseGeocodeText(
      lat,
      lng,
    ).timeout(const Duration(seconds: 4));
    if (label != 'Unknown location') {
      _addr[key] = label;
      return label;
    }
    return '(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  Future<void> _refreshRatedFlagsForCompleted(
    List<Map<String, dynamic>> justFetched,
  ) async {
    final me = sb.auth.currentUser?.id;
    if (me == null) return;

    final ids = <String>{};
    for (final r in justFetched) {
      final status = (r['effective_status'] as String?)?.toLowerCase();
      final id = r['id']?.toString();
      if (id != null && status == 'completed') ids.add(id);
    }
    if (ids.isEmpty) return;

    try {
      final rows = await sb
          .from('ratings')
          .select('ride_id')
          .eq('rater_user_id', me)
          .inFilter('ride_id', ids.toList());

      final rated =
          rows
              .map((e) => (e as Map)['ride_id']?.toString())
              .whereType<String>()
              .toSet();

      if (!mounted) return;
      setState(() {
        _ratedRideIds
          ..removeWhere((id) => ids.contains(id))
          ..addAll(rated);
      });
    } catch (_) {}
  }

  Future<void> _cancelRide(String rideId, {String? reason}) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await sb.rpc<void>(
        'cancel_ride',
        params: {'p_ride_id': rideId, 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ride canceled')));
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
                const Text('You can optionally tell the driver why.'),
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
      case 'canceled':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.black87;
    }
  }

  Widget _statusPill(String s) {
    final c = _statusColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: c,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _peso(num? v) =>
      v == null ? '₱0.00' : '₱${v.toDouble().toStringAsFixed(2)}';

  DateTime _toLocalTs(dynamic v) {
    if (v == null) return DateTime.now();
    final dt = v is DateTime ? v : DateTime.tryParse(v.toString());
    if (dt == null) return DateTime.now();
    return dt.toLocal();
  }

  Widget _rideCard(Map<String, dynamic> ride, {required bool upcoming}) {
    final status = (ride['effective_status'] as String? ?? '').toLowerCase();
    final createdLocal = _toLocalTs(ride['created_at']);
    final created = DateFormat('MMM d, y • h:mm a').format(createdLocal);

    final fare = (ride['fare'] as num?)?.toDouble();

    final pLat = (ride['pickup_lat'] as num?)?.toDouble();
    final pLng = (ride['pickup_lng'] as num?)?.toDouble();
    final dLat = (ride['destination_lat'] as num?)?.toDouble();
    final dLng = (ride['destination_lng'] as num?)?.toDouble();

    final rideId = ride['id'].toString();
    final driverId = ride['driver_id'] as String?;
    final driverName = ride['driver_name'] as String?;

    final needsRating =
        status == 'completed' &&
        driverId != null &&
        !_ratedRideIds.contains(rideId);

    final pickupAddress = ride['pickup_address']?.toString();
    final destinationAddress = ride['destination_address']?.toString();

    final pickupText =
        pickupAddress ??
        (pLat != null && pLng != null
            ? '(${pLat.toStringAsFixed(4)}, ${pLng.toStringAsFixed(4)})'
            : 'Pickup');
    final destText =
        destinationAddress ??
        (dLat != null && dLng != null
            ? '(${dLat.toStringAsFixed(4)}, ${dLng.toStringAsFixed(4)})'
            : 'Destination');

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
            if (pLat != null && pLng != null && dLat != null && dLng != null)
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
                            color: _purpleDark.withValues(alpha: .9),
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
                                  color: Colors.green,
                                ),
                              ),
                              Marker(
                                point: LatLng(dLat, dLng),
                                width: 28,
                                height: 28,
                                child: const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            if (pLat != null && pLng != null && dLat != null && dLng != null)
              const SizedBox(height: 10),
            Text(
              '$pickupText → $destText',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
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
                          : 'Driver: ${driverName ?? driverId.substring(0, 8)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
                _statusPill(status),
              ],
            ),
            const SizedBox(height: 10),
            if (upcoming)
              Row(
                children: [
                  if (status == 'pending' || status == 'accepted')
                    Expanded(
                      child: _primaryButton(
                        label: _working ? 'Cancelling…' : 'Cancel Ride',
                        icon: Icons.close,
                        onPressed: () => _confirmCancel(rideId),
                      ),
                    ),
                ],
              ),
            if (!upcoming && needsRating)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.star),
                  label: const Text('Rate your driver'),
                  onPressed: () async {
                    final me = sb.auth.currentUser?.id;
                    if (me == null) return;
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder:
                          (_) => RateUserSheet(
                            rideId: rideId,
                            raterUserId: me,
                            rateeUserId: driverId,
                            rateeName: driverName ?? 'Driver',
                            rateeRole: 'driver',
                          ),
                    );
                    await _refreshRatedFlagsForCompleted([ride]);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.chevron_right),
                label: const Text('View details'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PassengerRideStatusPage(rideId: rideId),
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

  Widget _searchBar() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Search by driver or address',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  Widget _filterChips({required bool upcoming}) {
    final items =
        upcoming
            ? const [
              ('all', 'All'),
              ('pending', 'Pending'),
              ('accepted', 'Accepted'),
              ('en_route', 'En route'),
            ]
            : const [
              ('all', 'All'),
              ('completed', 'Completed'),
              ('canceled', 'Canceled'),
            ];
    final current = upcoming ? _upcomingFilter : _historyFilter;
    return Wrap(
      spacing: 8,
      children:
          items.map((e) {
            final value = e.$1;
            final label = e.$2;
            final selected = current == value;
            return ChoiceChip(
              selected: selected,
              label: Text(label),
              onSelected:
                  (_) => setState(() {
                    if (upcoming) {
                      _upcomingFilter = value;
                    } else {
                      _historyFilter = value;
                    }
                  }),
            );
          }).toList(),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon:
            icon == null
                ? const SizedBox.shrink()
                : Icon(icon, color: Colors.white, size: 18),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
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
              ),
            ),
          ),
          title: Text(
            'My Rides',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorStateCard(
              title: 'Failed to load rides',
              message: _error!,
              ctaLabel: 'Retry',
              onCta: _bootstrap,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
              ),
            ),
          ),
          title: Text(
            'My Rides',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
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
                        color: Colors.black.withValues(alpha: 0.05),
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
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _searchBar(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _bootstrap,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _filterChips(upcoming: true),
                        const SizedBox(height: 6),
                        ...() {
                          final list =
                              _filterRides(_upcoming, upcoming: true);
                          if (list.isEmpty) {
                            return [
                              const SizedBox(height: 24),
                              EmptyStateCard(
                                icon: Icons.event_note,
                                title: 'No upcoming rides',
                                subtitle:
                                    'Book a ride to see it appear here.',
                                ctaLabel: 'Book a ride',
                                onCta:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder:
                                            (_) => const PassengerMapPage(),
                                      ),
                                    ),
                              ),
                            ];
                          }
                          return list.map(
                            (r) => _rideCard(r, upcoming: true),
                          );
                        }(),
                      ],
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: _bootstrap,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _filterChips(upcoming: false),
                        const SizedBox(height: 6),
                        ...() {
                          final list =
                              _filterRides(_history, upcoming: false);
                          if (list.isEmpty) {
                            return [
                              const SizedBox(height: 24),
                              const EmptyStateCard(
                                icon: Icons.event_note,
                                title: 'No ride history yet',
                                subtitle:
                                    'Completed rides will show up here.',
                              ),
                            ];
                          }
                          return list.map(
                            (r) => _rideCard(r, upcoming: false),
                          );
                        }(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
