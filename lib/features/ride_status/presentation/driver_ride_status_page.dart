// lib/features/ride_status/presentation/driver_ride_status_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Chat / Ratings / Safety
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/presentation/rating_details_sheet.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/safety/presentation/sos_sheet.dart';

// Live markers/helpers
import 'package:godavao/features/live_tracking/presentation/driver_marker.dart';
import 'package:godavao/features/live_tracking/presentation/passenger_marker.dart';
import 'package:godavao/features/live_tracking/utils/live_tracking_helpers.dart';

// Publish driver live location
import 'package:godavao/features/live_tracking/data/live_publisher.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, super.key});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage>
    with SingleTickerProviderStateMixin {
  final sb = Supabase.instance.client;

  // Realtime channels
  RealtimeChannel? _rideChannel;
  RealtimeChannel? _driverLiveChan;
  RealtimeChannel? _passengerLiveChan;
  RealtimeChannel? _feeChannel;

  // Map control (+ safe center until ready)
  final MapController _map = MapController();
  bool _mapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;
  void _safeMove(LatLng c, double z) {
    if (_mapReady) {
      _map.move(c, z);
    } else {
      _pendingCenter = c;
      _pendingZoom = z;
    }
  }

  // Page state
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _ride;
  String? _matchId;

  // Passenger identity & ratings
  String? _passengerId; // users.id
  bool _fetchingPassengerAgg = false;
  Map<String, dynamic>? _passengerAggregate;

  // Live driver interpolation (this device)
  LatLng? _driverPrev, _driverNext, _driverInterp;
  double _driverHeading = 0;
  late final AnimationController _driverAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addListener(_onDriverTick);

  // Live passenger
  LatLng? _passengerLive;

  // fare + fee
  double? _fare; // gross ride value
  double _platformFeeRate = 0.15; // default until dashboard loads

  // Camera/UX
  bool _followDriver = true;
  bool _ratingPromptShown = false;

  // Publisher for THIS driver
  late final LivePublisher _publisher = LivePublisher(
    sb,
    userId: sb.auth.currentUser!.id,
    rideId: widget.rideId,
    actor: 'driver',
  );

  // Theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _initFee();
    _loadAll();
  }

  @override
  void dispose() {
    _publisher.stop();
    _rideChannel._kill(sb);
    _driverLiveChan._kill(sb);
    _passengerLiveChan._kill(sb);
    _feeChannel._kill(sb);
    _driverAnim.dispose();
    super.dispose();
  }

  // ===================== fee =====================

  Future<void> _initFee() async {
    await _loadFeeFromDb();
    _subscribeFee();
  }

  Future<void> _loadFeeFromDb() async {
    try {
      final row =
          await sb
              .from('app_settings')
              .select('key, value, value_num')
              .eq('key', 'platform_fee_rate')
              .maybeSingle();

      final rate = _parseFeeRate(row);
      if (rate != null && rate >= 0 && rate <= 1) {
        setState(() => _platformFeeRate = rate);
      }
    } catch (_) {
      // ignore, keep default
    }
  }

  void _subscribeFee() {
    if (_feeChannel != null) return;
    _feeChannel =
        sb.channel('app_settings:platform_fee_rate:view')
          ..onPostgresChanges(
            schema: 'public',
            table: 'app_settings',
            event: PostgresChangeEvent.insert,
            callback: (payload) {
              final rec = payload.newRecord as Map?;
              if (rec == null) return;
              if (rec['key']?.toString() != 'platform_fee_rate') return;
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
              if (rec == null) return;
              if (rec['key']?.toString() != 'platform_fee_rate') return;
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
    if (s == null) return null;
    return double.tryParse(s);
  }

  // ===================== LOAD ALL =====================

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ride =
          await sb
              .from('ride_requests')
              .select('''
            id,
            pickup_lat, pickup_lng,
            destination_lat, destination_lng,
            status,
            passenger_id,
            fare
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (ride == null) throw Exception('Ride not found');
      _ride = Map<String, dynamic>.from(ride as Map);
      _fare = (_ride?['fare'] as num?)?.toDouble();

      final match =
          await sb
              .from('ride_matches')
              .select('id')
              .eq('ride_request_id', widget.rideId)
              .maybeSingle();
      _matchId = (match as Map?)?['id']?.toString();

      _passengerId = _ride?['passenger_id']?.toString();
      if (_passengerId != null) _fetchPassengerAggregate();

      await _seedLive('driver');
      await _seedLive('passenger');

      _safeMove(_pickup, 13);

      _subscribeRideStatus();
      _subscribeLive('driver');
      _subscribeLive('passenger');

      _syncPublisherToStatus(status);

      await _maybePromptRatingIfCompleted();
    } on PostgrestException catch (e) {
      _error = 'Supabase error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPassengerAggregate() async {
    if (_passengerId == null || !mounted) return;
    setState(() => _fetchingPassengerAgg = true);
    try {
      final agg = await RatingsService(sb).fetchUserAggregate(_passengerId!);
      if (!mounted) return;
      setState(() => _passengerAggregate = agg);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _fetchingPassengerAgg = false);
    }
  }

  // ===================== SUPABASE LIVE =====================

  void _subscribeRideStatus() {
    _rideChannel =
        sb.channel('ride_requests:${widget.rideId}')
          ..onPostgresChanges(
            schema: 'public',
            table: 'ride_requests',
            event: PostgresChangeEvent.update,
            callback: (payload) async {
              final newRec = payload.newRecord;
              if (newRec == null) return;
              if (newRec['id']?.toString() != widget.rideId) return;

              final updated = Map<String, dynamic>.from(newRec);
              if (!mounted) return;

              setState(() {
                _ride = updated;
                _fare = (updated['fare'] as num?)?.toDouble();
              });

              if (status == 'en_route') setState(() => _followDriver = true);
              _syncPublisherToStatus(status);

              final pid = updated['passenger_id']?.toString();
              if (pid != null && pid != _passengerId) {
                _passengerId = pid;
                _fetchPassengerAggregate();
              }

              await _maybePromptRatingIfCompleted();
            },
          )
          ..subscribe();
  }

  void _subscribeLive(String actor) {
    final chan =
        sb.channel('live_locations:${widget.rideId}:$actor')
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.insert,
            callback: (p) {
              final r = p.newRecord;
              if (r == null) return;
              if (r['ride_id']?.toString() == widget.rideId &&
                  r['actor']?.toString() == actor) {
                _onLiveRow(actor, r);
              }
            },
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.update,
            callback: (p) {
              final r = p.newRecord;
              if (r == null) return;
              if (r['ride_id']?.toString() == widget.rideId &&
                  r['actor']?.toString() == actor) {
                _onLiveRow(actor, r);
              }
            },
          )
          ..subscribe();

    if (actor == 'driver') {
      _driverLiveChan = chan;
    } else {
      _passengerLiveChan = chan;
    }
  }

  Future<void> _seedLive(String actor) async {
    final res =
        await sb
            .from('live_locations')
            .select('lat,lng,heading')
            .eq('ride_id', widget.rideId)
            .eq('actor', actor)
            .maybeSingle();

    if (res == null) return;
    final lat = (res['lat'] as num?)?.toDouble();
    final lng = (res['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    if (actor == 'driver') {
      _consumeDriverLocation({
        'lat': lat,
        'lng': lng,
        'heading': (res['heading'] as num?)?.toDouble(),
      });
    } else {
      if (!mounted) return;
      setState(() => _passengerLive = LatLng(lat, lng));
    }
  }

  void _onLiveRow(String actor, Map row) {
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    if (actor == 'driver') {
      _consumeDriverLocation(row);
    } else {
      if (!mounted) return;
      setState(() => _passengerLive = LatLng(lat, lng));
    }
  }

  // ===================== driver interp =====================

  void _consumeDriverLocation(Map rec) {
    final lat = (rec['lat'] as num?)?.toDouble();
    final lng = (rec['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final next = LatLng(lat, lng);
    final hdg = (rec['heading'] as num?)?.toDouble() ?? _driverHeading;

    if (!mounted) return;
    setState(() {
      _driverPrev = _driverInterp ?? _driverNext ?? next;
      _driverNext = next;
      _driverHeading = hdg;
      _driverAnim
        ..reset()
        ..forward();
    });
  }

  void _onDriverTick() {
    if (_driverPrev == null || _driverNext == null) return;
    final t = _driverAnim.value;
    final p = LiveTrackingHelpers.lerp(_driverPrev!, _driverNext!, t);

    if (!mounted) return;
    setState(() => _driverInterp = p);

    if (_followDriver && status == 'en_route') {
      final z = _mapReady ? _map.camera.zoom : 15.0;
      _safeMove(p, z.clamp(14, 16));
    }
  }

  // ===================== toggle publisher =====================

  void _syncPublisherToStatus(String s) {
    if (s == 'accepted' || s == 'en_route') {
      _publisher.start(); // idempotent
    } else {
      _publisher.stop();
    }
  }

  // ===================== ratings =====================

  Future<void> _maybePromptRatingIfCompleted() async {
    if (_ratingPromptShown) return;
    if (status != 'completed') return;

    final me = sb.auth.currentUser?.id;
    if (me == null || _passengerId == null) return;

    final existing = await RatingsService(sb).getExistingRating(
      rideId: widget.rideId,
      raterUserId: me,
      rateeUserId: _passengerId!,
    );
    if (existing != null) return;

    if (!mounted) return;
    _ratingPromptShown = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => RateUserSheet(
            rideId: widget.rideId,
            raterUserId: me,
            rateeUserId: _passengerId!,
            rateeName: 'Passenger',
            rateeRole: 'passenger',
          ),
    );

    await _fetchPassengerAggregate();
  }

  // ===================== helpers/getters =====================

  LatLng get _pickup => LatLng(
    (_ride!['pickup_lat'] as num).toDouble(),
    (_ride!['pickup_lng'] as num).toDouble(),
  );

  LatLng get _dest => LatLng(
    (_ride!['destination_lat'] as num).toDouble(),
    (_ride!['destination_lng'] as num).toDouble(),
  );

  String get status => (_ride?['status'] as String?) ?? 'pending';

  String _peso(num? v) =>
      v == null ? '₱0.00' : '₱${(v.toDouble()).toStringAsFixed(2)}';
  double? _driverNet(num? fare) =>
      fare == null ? null : (fare.toDouble() * (1 - _platformFeeRate));

  Widget _statusPill(String s) {
    final c = _statusColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.toUpperCase(),
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

  Widget _primaryGradientButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [_purple, _purpleDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _purple.withOpacity(0.25),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon:
              icon == null
                  ? const SizedBox.shrink()
                  : Icon(icon, color: Colors.white),
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
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  // ===================== build =====================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (_ride == null) {
      return const Scaffold(body: Center(child: Text('No ride data')));
    }

    final pickup = _pickup;
    final dest = _dest;

    final passengerRatingText = () {
      if (_fetchingPassengerAgg) return 'Loading…';
      final avg = (_passengerAggregate?['avg_rating'] as num?)?.toDouble();
      final cnt = (_passengerAggregate?['rating_count'] as int?) ?? 0;
      if (avg == null) return 'No ratings yet';
      return '${avg.toStringAsFixed(2)} ★  ($cnt)';
    }();

    final driverPoint = _driverInterp ?? _driverNext ?? pickup;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Driver Ride Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _followDriver ? 'Disable follow' : 'Enable follow',
            onPressed: () => setState(() => _followDriver = !_followDriver),
            icon: Icon(
              _followDriver ? Icons.my_location : Icons.location_disabled,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red.shade700,
        icon: const Icon(Icons.emergency_share),
        label: const Text('SOS'),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => SosSheet(rideId: widget.rideId),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: [
          // Map
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: pickup,
                initialZoom: 13,
                onMapReady: () {
                  setState(() => _mapReady = true);
                  if (_pendingCenter != null) {
                    _map.move(
                      _pendingCenter!,
                      _pendingZoom ?? _map.camera.zoom,
                    );
                    _pendingCenter = null;
                    _pendingZoom = null;
                  }
                },
                onTap: (_, __) {
                  if (_followDriver) setState(() => _followDriver = false);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.godavao.app',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, dest],
                      strokeWidth: 5,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Driver live (this device)
                    Marker(
                      point: driverPoint,
                      width: 48,
                      height: 56,
                      alignment: Alignment.center,
                      child: DriverMarker(
                        size: 36,
                        headingDeg: _driverHeading,
                        active: status == 'en_route' || status == 'accepted',
                      ),
                    ),
                    // Passenger live (if available) else pickup
                    Marker(
                      point: _passengerLive ?? pickup,
                      width: 36,
                      height: 44,
                      child:
                          _passengerLive == null
                              ? const Icon(
                                Icons.location_on,
                                color: Colors.green,
                                size: 38,
                              )
                              : const PassengerMarker(size: 26, ripple: true),
                    ),
                    // Destination
                    Marker(
                      point: dest,
                      width: 38,
                      height: 38,
                      child: const Icon(
                        Icons.flag,
                        color: Colors.red,
                        size: 38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Text(
                          'Passenger',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        if (_passengerId != null)
                          VerifiedBadge(userId: _passengerId!, size: 18),
                        const Spacer(),
                        Flexible(child: _statusPill(status)),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Ratings summary
                    if (_passengerId != null)
                      Row(
                        children: [
                          UserRatingBadge(userId: _passengerId!, iconSize: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              passengerRatingText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder:
                                    (_) => RatingDetailsSheet(
                                      userId: _passengerId!,
                                      title: 'Passenger feedback',
                                    ),
                              );
                            },
                            child: const Text('View feedback'),
                          ),
                        ],
                      ),

                    // ==== Earnings breakdown ====
                    if (_fare != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.receipt_long,
                                  size: 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Ride value',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                Text(
                                  _peso(_fare),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.percent,
                                  size: 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Platform fee (${(_platformFeeRate * 100).toStringAsFixed(0)}%)',
                                ),
                                const Spacer(),
                                Text('- ${_peso(_fare! * _platformFeeRate)}'),
                              ],
                            ),
                            const Divider(height: 14),
                            Row(
                              children: [
                                const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Your take',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                Text(
                                  _peso(_driverNet(_fare)),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Center controls + Chat
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            final p = _driverInterp ?? _driverNext;
                            if (p != null) {
                              final z = _mapReady ? _map.camera.zoom : 15.0;
                              _safeMove(p, math.max(z, 15));
                              setState(() => _followDriver = true);
                            }
                          },
                          icon: const Icon(Icons.center_focus_strong, size: 16),
                          label: const Text('Center on me'),
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: () => _safeMove(_dest, 15),
                          icon: const Icon(Icons.place, size: 16),
                          label: const Text('Destination'),
                        ),
                        const Spacer(),
                        if (_matchId != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.message),
                            label: const Text('Chat'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(matchId: _matchId!),
                                ),
                              );
                            },
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Rate after completed
                    if (status == 'completed' && _passengerId != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.star),
                          label: const Text('Rate your passenger'),
                          onPressed:
                              () async => _maybePromptRatingIfCompleted(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----- helpers -----
extension _Kill on RealtimeChannel? {
  void _kill(SupabaseClient sb) {
    final c = this;
    if (c != null) sb.removeChannel(c);
  }
}
