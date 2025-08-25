import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Chat / Payments / Ratings / Safety
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/payments/presentation/gcash_proof_sheet.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/presentation/rating_details_sheet.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/safety/presentation/sos_sheet.dart';

// Live tracking bits
import 'package:godavao/features/live_tracking/presentation/driver_marker.dart';
import 'package:godavao/features/live_tracking/presentation/passenger_marker.dart';
import 'package:godavao/features/live_tracking/utils/live_tracking_helpers.dart';

// Publish passenger live location
import 'package:godavao/features/live_tracking/data/live_publisher.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String rideId;
  const PassengerRideStatusPage({required this.rideId, super.key});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  // Realtime channels
  RealtimeChannel? _rideChannel;
  RealtimeChannel? _driverLocChannel;
  RealtimeChannel? _selfLocChannel;

  // Map + readiness guard
  final MapController _map = MapController();
  bool _mapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;
  void _safeMove(LatLng center, double zoom) {
    if (_mapReady) {
      _map.move(center, zoom);
    } else {
      _pendingCenter = center;
      _pendingZoom = zoom;
    }
  }

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _ride;
  String? _matchId;

  // Driver identity + ratings
  String? _driverId;
  Map<String, dynamic>? _driverAggregate;
  bool _fetchingDriverAgg = false;

  // Live driver state for nice interpolation
  LatLng? _driverPrev, _driverNext, _driverInterp;
  double _driverHeading = 0;

  // Passenger live
  LatLng? _selfLive;

  // Follow camera toggle
  bool _followDriver = true;

  // Avoid duplicate rating modals
  bool _ratingPromptShown = false;

  // Animate car between points
  late final AnimationController _driverAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addListener(_onDriverTick);

  // Publish THIS passenger’s live location
  late final LivePublisher _publisher = LivePublisher(
    _sb,
    userId: _sb.auth.currentUser!.id,
    rideId: widget.rideId,
    actor: 'passenger',
  );

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _loadRideDetails();
    _subscribeRideStatus();

    // Subscribe to *my* live row so I can see my own dot move (optional)
    final me = _sb.auth.currentUser?.id;
    if (me != null) _subscribeSelfLive(me);
  }

  @override
  void dispose() {
    _publisher.stop();
    _rideChannel?.let(_sb.removeChannel);
    _driverLocChannel?.let(_sb.removeChannel);
    _selfLocChannel?.let(_sb.removeChannel);
    _driverAnim.dispose();
    super.dispose();
  }

  // ---------------- Data ----------------

  Future<void> _loadRideDetails() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Ride
      final ride =
          await _sb
              .from('ride_requests')
              .select('''
                id,
                pickup_lat, pickup_lng,
                destination_lat, destination_lng,
                status,
                fare,
                payment_method,
                driver_route_id
              ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (ride == null) throw Exception('Ride not found');
      _ride = (ride as Map).cast<String, dynamic>();

      // Match
      final match =
          await _sb
              .from('ride_matches')
              .select('id')
              .eq('ride_request_id', widget.rideId)
              .maybeSingle();
      if (match == null) throw Exception('No match found for this ride');
      _matchId = (match as Map)['id']?.toString();

      // Driver id + rating agg + subscribe to driver live
      await _resolveDriver();

      // Move map to pickup
      final pickup = LatLng(
        (_ride!['pickup_lat'] as num).toDouble(),
        (_ride!['pickup_lng'] as num).toDouble(),
      );
      _safeMove(pickup, 13);

      // Start/stop publishing my location depending on status
      _syncPublisherToStatus((_ride!['status'] ?? '').toString());

      // If already completed, maybe prompt rating
      await _maybePromptRatingIfCompleted();
    } on PostgrestException catch (e) {
      _error = 'Supabase error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveDriver() async {
    final driverRouteId = _ride?['driver_route_id'];
    if (driverRouteId == null) return;

    final dr =
        await _sb
            .from('driver_routes')
            .select('driver_id')
            .eq('id', driverRouteId)
            .maybeSingle();

    if (dr != null) {
      _driverId = (dr as Map)['driver_id']?.toString();
      if (_driverId != null) {
        _subscribeDriverLive(_driverId!);
        await _fetchDriverAggregate();
      }
    }
  }

  Future<void> _fetchDriverAggregate() async {
    if (_driverId == null || !mounted) return;
    setState(() => _fetchingDriverAgg = true);
    try {
      final service = RatingsService(_sb);
      final agg = await service.fetchUserAggregate(_driverId!);
      if (!mounted) return;
      setState(() => _driverAggregate = agg);
    } catch (_) {
      // ignore; best effort
    } finally {
      if (mounted) setState(() => _fetchingDriverAgg = false);
    }
  }

  // ------------- Live publish toggle -------------

  void _syncPublisherToStatus(String status) {
    // Publish while we still need the driver to locate the passenger.
    if (status == 'pending' || status == 'accepted' || status == 'en_route') {
      _publisher.start();
    } else {
      _publisher.stop();
    }
  }

  // ------------- Realtime subscriptions -----------

  void _subscribeRideStatus() {
    _rideChannel =
        _sb
            .channel('ride_requests:${widget.rideId}')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_requests',
              event: PostgresChangeEvent.update,
              callback: (payload) async {
                final newRec = payload.newRecord;
                final updated = (newRec as Map).cast<String, dynamic>();
                if (updated['id'] != widget.rideId) return;

                if (!mounted) return;
                setState(() => _ride = updated);

                // Auto follow while en_route
                if ((updated['status'] ?? '') == 'en_route') {
                  setState(() => _followDriver = true);
                }

                // If driver assignment changed, re-resolve
                await _resolveDriver();

                // Start/stop passenger publisher based on status
                _syncPublisherToStatus((updated['status'] ?? '').toString());

                await _maybePromptRatingIfCompleted();
              },
            )
            .subscribe();
  }

  void _subscribeDriverLive(String driverUserId) {
    _driverLocChannel =
        _sb
            .channel('live_locations_driver_$driverUserId')
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.insert,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: driverUserId,
              ),
              callback: (payload) {
                final rec = payload.newRecord;
                _consumeDriverLocation(rec);
              },
            )
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.update,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: driverUserId,
              ),
              callback: (payload) {
                final rec = payload.newRecord;
                _consumeDriverLocation(rec);
              },
            )
            .subscribe();
  }

  void _subscribeSelfLive(String selfUserId) {
    _selfLocChannel =
        _sb
            .channel('live_locations_self_$selfUserId')
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.insert,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: selfUserId,
              ),
              callback: (payload) {
                final rec = payload.newRecord;
                final lat = (rec['lat'] as num?)?.toDouble();
                final lng = (rec['lng'] as num?)?.toDouble();
                if (lat == null || lng == null) return;
                if (!mounted) return;
                setState(() => _selfLive = LatLng(lat, lng));
              },
            )
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.update,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: selfUserId,
              ),
              callback: (payload) {
                final rec = payload.newRecord;
                final lat = (rec['lat'] as num?)?.toDouble();
                final lng = (rec['lng'] as num?)?.toDouble();
                if (lat == null || lng == null) return;
                if (!mounted) return;
                setState(() => _selfLive = LatLng(lat, lng));
              },
            )
            .subscribe();
  }

  // -------- driver interpolation ----------

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

    // Follow while en_route
    final status = (_ride?['status'] ?? '').toString();
    if (_followDriver && status == 'en_route') {
      final z = _mapReady ? _map.camera.zoom : 15.0;
      _safeMove(p, z.clamp(14, 16));
    }
  }

  // ------------- Ratings -----------------

  Future<void> _maybePromptRatingIfCompleted() async {
    if (_ratingPromptShown) return;
    final status = _ride?['status']?.toString();
    if (status != 'completed') return;

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    if (_driverId == null) return;

    final service = RatingsService(_sb);
    final existing = await service.getExistingRating(
      rideId: widget.rideId,
      raterUserId: uid,
      rateeUserId: _driverId!,
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
            raterUserId: uid,
            rateeUserId: _driverId!,
            rateeName: 'Driver',
            rateeRole: 'driver',
          ),
    );

    await _fetchDriverAggregate();
  }

  // ------------- UI helpers ---------------

  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
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
              offset: const Offset(0, 8),
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

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }

    if (_ride == null || _matchId == null) {
      return const Scaffold(body: Center(child: Text('No ride data')));
    }

    final r = _ride!;
    final pickup = LatLng(
      (r['pickup_lat'] as num).toDouble(),
      (r['pickup_lng'] as num).toDouble(),
    );
    final dest = LatLng(
      (r['destination_lat'] as num).toDouble(),
      (r['destination_lng'] as num).toDouble(),
    );

    final status = (r['status'] as String?) ?? 'pending';
    final fare = (r['fare'] as num?)?.toDouble() ?? 0.0;

    final driverRatingText = () {
      if (_fetchingDriverAgg) return 'Loading…';
      final avg = (_driverAggregate?['avg_rating'] as num?)?.toDouble();
      final cnt = (_driverAggregate?['rating_count'] as int?) ?? 0;
      if (avg == null) return 'No ratings yet';
      return '${avg.toStringAsFixed(2)} ★  ($cnt)';
    }();

    final canUploadGcash =
        (status == 'accepted' ||
            status == 'en_route' ||
            status == 'completed') &&
        (r['payment_method'] == 'gcash');

    // Driver marker position preference: live interp > next > pickup
    final driverPoint = _driverInterp ?? _driverNext ?? pickup;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Ride Details'),
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
                center: pickup,
                zoom: 13,
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
                // Simple straight line preview
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, dest],
                      strokeWidth: 5,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ],
                ),
                // Markers
                MarkerLayer(
                  markers: [
                    // Driver live
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
                    // Myself (passenger) — live if available; else pickup
                    Marker(
                      point: _selfLive ?? pickup,
                      width: 36,
                      height: 44,
                      child:
                          _selfLive == null
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
                          'Driver',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        if (_driverId != null)
                          VerifiedBadge(userId: _driverId!, size: 18),
                        const Spacer(),
                        _statusPill(status),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Ratings
                    if (_driverId != null)
                      Row(
                        children: [
                          UserRatingBadge(userId: _driverId!, iconSize: 16),
                          const SizedBox(width: 6),
                          Text(
                            driverRatingText,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder:
                                    (_) => RatingDetailsSheet(
                                      userId: _driverId!,
                                      title: 'Driver feedback',
                                    ),
                              );
                            },
                            child: const Text('View feedback'),
                          ),
                        ],
                      ),

                    const SizedBox(height: 8),

                    // Fare + center
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Fare: ₱${fare.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
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
                          label: const Text('Center'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // GCash
                    if (canUploadGcash) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.account_balance_wallet),
                          label: const Text('Pay with GCash (upload proof)'),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder:
                                  (_) => GcashProofSheet(
                                    rideId: widget.rideId,
                                    amount: fare,
                                  ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Chat
                    Row(
                      children: [
                        Expanded(
                          child: _primaryGradientButton(
                            label: 'Chat with Driver',
                            icon: Icons.message,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(matchId: _matchId!),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    // Rate after completed
                    if (status == 'completed' && _driverId != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.star),
                          label: const Text('Rate your driver'),
                          onPressed:
                              () async => _maybePromptRatingIfCompleted(),
                        ),
                      ),
                    ],
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

// tiny helpers
extension _Chan on RealtimeChannel {
  void let(void Function(RealtimeChannel ch) f) => f(this);
}
