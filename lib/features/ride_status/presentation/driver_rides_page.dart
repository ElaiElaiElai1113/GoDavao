import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/admin_menu_action.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// global notifications instance
import 'package:godavao/main.dart' show localNotify;

// rating badge beside passenger name (already in your file)
import 'package:godavao/features/ratings/presentation/user_rating.dart';

// rating sheet + service
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';

// verified badge
import 'package:godavao/features/verify/presentation/verified_badge.dart';

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

  List<LatLng> _routePoints = [];
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _declined = [];
  List<Map<String, dynamic>> _completed = [];
  final Set<String> _newMatchIds = {};

  // ride_request_id -> {status, amount}
  Map<String, Map<String, dynamic>> _paymentByRide = {};

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
        _paymentByRide = {};
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

    // 2) fetch ride_matches + nested ride_requests + passenger (id + name) + fare
    final raw = await _supabase
        .from('ride_matches')
        .select(r'''
          id,
          ride_request_id,
          status,
          created_at,
          ride_requests (
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng,
            passenger_id,
            fare,
     
            users ( id, name )
          )
        ''')
        .eq('driver_route_id', routeData['id'] as String)
        .order('created_at', ascending: true);

    // 3) enrich + split
    final all = <Map<String, dynamic>>[];
    final rideIds = <String>[];

    for (final m in raw as List) {
      final req = m['ride_requests'] as Map<String, dynamic>?;
      if (req == null) continue;

      // Passenger name/id (map or list)
      String? passengerName;
      String? passengerId;
      final usersRel = req['users'];
      if (usersRel is Map) {
        passengerName = usersRel['name'] as String?;
        passengerId = usersRel['id']?.toString();
      } else if (usersRel is List &&
          usersRel.isNotEmpty &&
          usersRel.first is Map) {
        final first = usersRel.first as Map;
        passengerName = (first['name'] as String?) ?? 'Unknown';
        passengerId = first['id']?.toString();
      }
      passengerId ??= req['passenger_id']?.toString();
      passengerName ??= 'Unknown';

      final pLat = (req['pickup_lat'] as num).toDouble();
      final pLng = (req['pickup_lng'] as num).toDouble();
      final dLat = (req['destination_lat'] as num).toDouble();
      final dLng = (req['destination_lng'] as num).toDouble();

      // reverse-geocode (best effort)
      String fmt(Placemark pm) => [
        pm.thoroughfare,
        pm.subLocality,
        pm.locality,
      ].where((s) => s != null && s.isNotEmpty).cast<String>().join(', ');
      final pMark = (await placemarkFromCoordinates(pLat, pLng)).first;
      final dMark = (await placemarkFromCoordinates(dLat, dLng)).first;

      // nearest point index to pickup for sorting
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

      final fare = (req['fare'] as num?)?.toDouble();

      final item = {
        'match_id': m['id'],
        'ride_request_id': m['ride_request_id'],
        'status': m['status'],
        'created_at': m['created_at'],
        'passenger': passengerName,
        'passenger_id': passengerId, // used by badges/rating
        'pickup_point': pickPt,
        'pickup_address': fmt(pMark),
        'destination_address': fmt(dMark),
        'route_index': bestI,
        'fare': fare,
      };

      all.add(item);
      rideIds.add(m['ride_request_id'] as String);
    }

    all.sort((a, b) => a['route_index'].compareTo(b['route_index']));

    // 4) fetch payment intents in bulk for these ride ids
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
    final ids = rideIds.toSet().toList();

    final res = await _supabase
        .from('payment_intents')
        .select('ride_id, status, amount')
        .inFilter('ride_id', ids);

    for (final row in (res as List)) {
      final rid = row['ride_id'] as String;
      _paymentByRide[rid] = {
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
                final m = payload.newRecord;
                final id = m['id'] as String;
                setState(() => _newMatchIds.add(id));
                _showNotification(
                  'New Request',
                  'A passenger requested a pickup.',
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

  Widget _paymentStatusBadge(String rideRequestId) {
    final pi = _paymentByRide[rideRequestId];
    if (pi == null) return const SizedBox.shrink();

    final status = (pi['status'] as String?) ?? '';
    late final Color bg;
    late final IconData icon;
    late final String label;

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
      case 'requires_proof':
        bg = Colors.blueGrey.shade100;
        icon = Icons.hourglass_top;
        label = 'REQUIRES PROOF';
        break;
      default:
        bg = Colors.grey.shade200;
        icon = Icons.help_outline;
        label = status.isEmpty ? 'NO INTENT' : status.toUpperCase();
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
        ],
      ),
    );
  }

  Widget _fareRow(Map<String, dynamic> m) {
    final fareNum = (m['fare'] as num?);
    final fare = fareNum?.toDouble();
    final method = m['payment_method'] as String?;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          fare != null ? 'Fare: ₱${fare.toStringAsFixed(2)}' : 'Fare: —',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (method != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              method.toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  // open rating sheet from a completed card
  Future<void> _ratePassenger(Map<String, dynamic> m) async {
    final uid = _supabase.auth.currentUser?.id;
    final rideId = m['ride_request_id']?.toString();
    final passengerId = m['passenger_id']?.toString();

    if (uid == null || rideId == null || passengerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing info to rate passenger.')),
      );
      return;
    }

    try {
      // Avoid double-rating this ride
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
              rateeName: m['passenger']?.toString() ?? 'Passenger',
              rateeRole: 'passenger',
            ),
      );
    } catch (e) {
      final msg = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open rating: $msg')));
    }
  }

  Widget _buildCard(Map<String, dynamic> m) {
    final id = m['match_id'] as String;
    final status = (m['status'] as String).toLowerCase();
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(m['created_at']));
    final passengerId = m['passenger_id'] as String?;
    final rideRequestId = m['ride_request_id'] as String;

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.horizontal,
      background: Container(
        color: Colors.red.shade100,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.close, color: Colors.red),
      ),
      secondaryBackground: Container(
        color: Colors.green.shade100,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.check, color: Colors.green),
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          _updateMatchStatus(id, m['ride_request_id'], 'declined');
        } else {
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

                // Passenger row + badges
                Row(
                  children: [
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

                // Fare + method
                _fareRow(m),

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
                    // Payment badge (if available)
                    _paymentStatusBadge(rideRequestId),
                  ],
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

                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                    ChatPage(matchId: m['match_id'] as String),
                          ),
                        );
                      },
                      child: const Icon(Icons.message),
                    ),

                    const SizedBox(width: 8),

                    // ⭐ Only on COMPLETED: show rate button
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
        ),
      ),
    );
  }

  void _showRideSheet(Map<String, dynamic> ride) {
    final id = ride['match_id'] as String;
    final status = (ride['status'] as String).toLowerCase();
    final pickup = ride['pickup_address'] as String;
    final dropoff = ride['destination_address'] as String;
    final passenger = ride['passenger'] as String;
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(ride['created_at']));
    final double? fare =
        (ride['fare'] as double?) ?? (ride['fare'] as num?)?.toDouble();
    final String? paymentMethod = ride['payment_method'] as String?;
    final String rideRequestId = ride['ride_request_id'] as String;

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
              if (fare != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Estimated fare: ₱${fare.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              if (paymentMethod != null) ...[
                const SizedBox(height: 2),
                Text('Payment method: ${paymentMethod.toUpperCase()}'),
              ],
              const SizedBox(height: 12),

              _paymentStatusBadge(rideRequestId),
              const SizedBox(height: 12),

              Text(
                'Status: ${status.toUpperCase()}',
                style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

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
                    const Center(child: Text('No actions available')),
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

    // Move between tabs
    setState(() {
      // remove from all
      Map<String, dynamic>? item;
      item ??= _upcoming.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['match_id'] == matchId,
        orElse: () => null,
      );
      item ??= _declined.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['match_id'] == matchId,
        orElse: () => null,
      );
      item ??= _completed.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['match_id'] == matchId,
        orElse: () => null,
      );

      _upcoming.removeWhere((e) => e['match_id'] == matchId);
      _declined.removeWhere((e) => e['match_id'] == matchId);
      _completed.removeWhere((e) => e['match_id'] == matchId);

      if (item != null) {
        item['status'] = newStatus;
        if (newStatus == 'declined') {
          _declined.insert(0, item);
        } else if (newStatus == 'completed') {
          _completed.insert(0, item);
          // Refresh payment badge for this ride only
          _loadPaymentIntents([rideRequestId]).then((_) => setState(() {}));
        } else {
          _upcoming.insert(0, item);
        }
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
                    // Upcoming with colored mini-map
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
                                        : const LatLng(0, 0),
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
                          ..._upcoming.map(_buildCard),
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
