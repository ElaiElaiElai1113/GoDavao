import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:godavao/main.dart' show localNotify;
import 'package:godavao/features/safety/presentation/sos_sheet.dart';

// Ratings
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/presentation/rating_details_sheet.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';

// Live tracking
import 'package:godavao/features/live_tracking/presentation/driver_marker.dart';
import 'package:godavao/features/live_tracking/presentation/passenger_marker.dart';
import 'package:godavao/features/live_tracking/utils/live_tracking_helpers.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, super.key});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _rideChannel;
  RealtimeChannel? _driverLocChannel;
  RealtimeChannel? _passengerLocChannel;

  final MapController _map = MapController();

  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _passenger;
  bool _loading = true;
  String? _error;
  bool _ratingPromptShown = false;

  // --- Live positions --------------------------------------------------------
  // Driver (this user)
  LatLng? _driverPrev;
  LatLng? _driverNext;
  LatLng? _driverInterp;
  double _driverHeading = 0;

  LatLng? _passengerLive;

  late final AnimationController _driverAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addListener(_onDriverTick);

  bool _followDriver = true;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _loadRide();
    _subscribeToRideUpdates();

    // Start listening to driver's live location
    final myId = supabase.auth.currentUser?.id;
    if (myId != null) _subscribeDriverLive(myId);
  }

  @override
  void dispose() {
    _rideChannel?.let(supabase.removeChannel);
    _driverLocChannel?.let(supabase.removeChannel);
    _passengerLocChannel?.let(supabase.removeChannel);
    _driverAnim.dispose();
    super.dispose();
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'rides_channel',
      'Ride Updates',
      channelDescription: 'Notifications for ride status changes',
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

  Future<void> _loadRide() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final r =
          await supabase
              .from('ride_requests')
              .select('''
            id,
            pickup_lat, pickup_lng,
            destination_lat, destination_lng,
            status,
            passenger_id,
            driver_route_id
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (r == null) throw Exception('Ride not found');
      _ride = Map<String, dynamic>.from(r as Map);

      // fetch passenger profile (best-effort)
      final pid = _ride!['passenger_id']?.toString();
      if (pid != null) {
        final u =
            await supabase
                .from('users')
                .select('id, name, avatar_url')
                .eq('id', pid)
                .maybeSingle();
        if (u != null) _passenger = Map<String, dynamic>.from(u as Map);

        _subscribePassengerLive(pid);
      }

      // center map to pickup initially
      final pickup = LatLng(
        (_ride!['pickup_lat'] as num).toDouble(),
        (_ride!['pickup_lng'] as num).toDouble(),
      );
      _map.move(pickup, 13);

      await _maybePromptRatingIfCompleted();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // --- Supabase realtime: ride status ---------------------------------------
  void _subscribeToRideUpdates() {
    _rideChannel =
        supabase
            .channel('ride_requests_${widget.rideId}')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_requests',
              event: PostgresChangeEvent.update,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: widget.rideId,
              ),
              callback: (payload) async {
                final updated = Map<String, dynamic>.from(payload.newRecord);
                if (!mounted) return;

                setState(() => _ride = updated);

                await _showNotification(
                  'Ride Update',
                  'Passenger status is now ${updated['status']}',
                );

                // Follow driver during en_route
                if ((updated['status'] ?? '') == 'en_route') {
                  _followDriver = true;
                }

                await _maybePromptRatingIfCompleted();
              },
            )
            .subscribe();
  }

  // --- Supabase realtime: driver live location ------------------------------
  void _subscribeDriverLive(String userId) {
    _driverLocChannel =
        supabase
            .channel('live_locations_driver_$userId')
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.insert,
              callback: (payload) {
                final rec = payload.newRecord;
                if (rec == null) return;
                if (rec['user_id']?.toString() != userId) return;
                _consumeDriverLocation(rec);
              },
            )
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.update,
              callback: (payload) {
                final rec = payload.newRecord;
                if (rec == null) return;
                if (rec['user_id']?.toString() != userId) return;
                _consumeDriverLocation(rec);
              },
            )
            .subscribe();
  }

  void _consumeDriverLocation(Map rec) {
    final lat = (rec['lat'] as num?)?.toDouble();
    final lng = (rec['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final next = LatLng(lat, lng);
    final hdg = (rec['heading'] as num?)?.toDouble() ?? _driverHeading;

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
    setState(() => _driverInterp = p);

    // Follow camera while en_route if enabled
    final status = (_ride?['status'] ?? '').toString();
    if (_followDriver && status == 'en_route') {
      // Small smoothing for zoom 15 following
      _map.move(p, _map.camera.zoom.clamp(14, 16));
    }
  }

  // --- Supabase realtime: passenger live location (optional) ----------------
  void _subscribePassengerLive(String passengerUserId) {
    _passengerLocChannel =
        supabase
            .channel('live_locations_passenger_$passengerUserId')
            .onPostgresChanges(
              schema: 'public',
              table: 'live_locations',
              event: PostgresChangeEvent.update,
              callback: (payload) {
                final rec = payload.newRecord;
                if (rec == null) return;
                if (rec['user_id']?.toString() != passengerUserId) return;
                final lat = (rec['lat'] as num?)?.toDouble();
                final lng = (rec['lng'] as num?)?.toDouble();
                if (lat == null || lng == null) return;
                setState(() => _passengerLive = LatLng(lat, lng));
              },
            )
            .subscribe();
  }

  // --- Ratings ---------------------------------------------------------------
  Future<void> _maybePromptRatingIfCompleted() async {
    if (_ratingPromptShown) return;
    final status = _ride?['status']?.toString();
    if (status != 'completed') return;

    final uid = supabase.auth.currentUser?.id;
    final passengerId = _ride?['passenger_id']?.toString();
    if (uid == null || passengerId == null) return;

    final existing = await RatingsService(supabase).getExistingRating(
      rideId: widget.rideId,
      raterUserId: uid,
      rateeUserId: passengerId,
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
            rateeUserId: passengerId,
            rateeName: _passenger?['name'] ?? 'Passenger',
            rateeRole: 'passenger',
          ),
    );
  }

  // --- UI helpers ------------------------------------------------------------
  Widget _statusPill(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
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
        return Colors.black87;
    }
  }

  // --- BUILD -----------------------------------------------------------------
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

    final r = _ride!;
    final pickup = LatLng(
      (r['pickup_lat'] as num).toDouble(),
      (r['pickup_lng'] as num).toDouble(),
    );
    final dest = LatLng(
      (r['destination_lat'] as num).toDouble(),
      (r['destination_lng'] as num).toDouble(),
    );
    final status = (r['status'] ?? '').toString();

    final passengerName = (_passenger?['name'] as String?) ?? 'Passenger';
    final passengerId = r['passenger_id']?.toString();

    // Driver marker position preference: live interp > next > pickup (fallback)
    final driverPoint = _driverInterp ?? _driverNext ?? pickup;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Driver Ride Details'),
        actions: [
          // Quick toggle for camera follow
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
                onTap: (_, __) {
                  // tapping map disables follow (user wants to explore)
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
                // Route overview (pickup -> dropoff)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, dest],
                      strokeWidth: 5,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ],
                ),
                // Live markers
                MarkerLayer(
                  markers: [
                    // Driver
                    Marker(
                      point: driverPoint,
                      width: 48,
                      height: 56,
                      alignment: Alignment.center,
                      child: DriverMarker(
                        size: 36,
                        headingDeg: _driverHeading,
                        active: status == 'en_route' || status == 'accepted',
                        label: null, // you can put plate string here
                      ),
                    ),
                    // Passenger: show live if available; else pickup pin
                    Marker(
                      point: _passengerLive ?? pickup,
                      width: 36,
                      height: 44,
                      child:
                          _passengerLive == null
                              ? const Icon(
                                Icons.location_pin,
                                color: Colors.green,
                                size: 36,
                              )
                              : const PassengerMarker(size: 26, ripple: true),
                    ),
                    // Destination
                    Marker(
                      point: dest,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.flag,
                        color: Colors.red,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom sheet summary
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Passenger row styled
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage:
                              (_passenger?['avatar_url'] != null &&
                                      (_passenger!['avatar_url'] as String)
                                          .isNotEmpty)
                                  ? NetworkImage(
                                    _passenger!['avatar_url'] as String,
                                  )
                                  : null,
                          child:
                              (_passenger?['avatar_url'] == null ||
                                      (_passenger!['avatar_url'] as String)
                                          .isEmpty)
                                  ? const Icon(
                                    Icons.person,
                                    color: Colors.black54,
                                  )
                                  : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      passengerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (passengerId != null)
                                    UserRatingBadge(
                                      userId: passengerId,
                                      iconSize: 14,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _statusPill(
                                    'Status: ${status.toUpperCase()}',
                                    icon: Icons.info_outline,
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap:
                                        passengerId == null
                                            ? null
                                            : () {
                                              showModalBottomSheet(
                                                context: context,
                                                isScrollControlled: true,
                                                builder:
                                                    (_) => RatingDetailsSheet(
                                                      userId: passengerId,
                                                      title:
                                                          'Passenger feedback',
                                                    ),
                                              );
                                            },
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.reviews,
                                          size: 16,
                                          color: Colors.black54,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'View feedback',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statusPill('Pickup', icon: Icons.location_pin),
                        const SizedBox(width: 8),
                        _statusPill('Dropoff', icon: Icons.flag),
                        const Spacer(),
                        // Quick “center on me” button
                        TextButton.icon(
                          onPressed: () {
                            final p = _driverInterp ?? _driverNext;
                            if (p != null)
                              _map.move(p, math.max(_map.camera.zoom, 15));
                            setState(() => _followDriver = true);
                          },
                          icon: const Icon(Icons.center_focus_strong, size: 16),
                          label: const Text('Center'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // CTA: Rate when completed
                    if (status == 'completed' && passengerId != null)
                      SizedBox(
                        height: 52,
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
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.star, color: Colors.white),
                            label: const Text(
                              'Rate your passenger',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            onPressed: () async {
                              _ratingPromptShown = false;
                              await _maybePromptRatingIfCompleted();
                            },
                          ),
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

// Small extension to avoid null checks when removing channels
extension _ChannelKill on RealtimeChannel {
  void let(void Function(RealtimeChannel ch) f) => f(this);
}
