import 'dart:async';
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

// Publisher (ride_id + actor)
import 'package:godavao/features/live_tracking/data/live_publisher.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, super.key});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // Realtime
  RealtimeChannel? _rideChannel;
  RealtimeChannel? _driverLiveChannel; // listens by (ride_id, actor='driver')
  RealtimeChannel? _passengerLiveChannel;

  // Map readiness
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

  // Data
  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _passenger;
  bool _loading = true;
  String? _error;
  bool _ratingPromptShown = false;

  // Live positions
  LatLng? _driverPrev, _driverNext, _driverInterp;
  double _driverHeading = 0;
  LatLng? _passengerLive;

  late final AnimationController _driverAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addListener(_onDriverTick);

  bool _followDriver = true;

  // Live publisher (driver)
  late final LivePublisher _publisher = LivePublisher(
    supabase,
    userId: supabase.auth.currentUser!.id,
    rideId: widget.rideId,
    actor: 'driver',
  );

  // Optional polling fallback if realtime drops
  Timer? _pollFallback;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _loadRide();
    _subscribeRideStatus();
    _subscribeDriverLive(widget.rideId); // listen for our own published updates
  }

  @override
  void dispose() {
    _rideChannel?.kill(supabase);
    _driverLiveChannel?.kill(supabase);
    _passengerLiveChannel?.kill(supabase);
    _driverAnim.dispose();
    _pollFallback?.cancel();
    _publisher.stop();
    super.dispose();
  }

  // -------------------------------------------------
  // Notifications
  Future<void> _notify(String title, String body) async {
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

  // -------------------------------------------------
  // Data load
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

      // center on pickup safely
      final pickup = LatLng(
        (_ride!['pickup_lat'] as num).toDouble(),
        (_ride!['pickup_lng'] as num).toDouble(),
      );
      _safeMove(pickup, 13);

      // fetch passenger + subscribe to passenger live
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

      _syncPublisherToStatus((_ride!['status'] ?? '').toString());
      await _maybePromptRatingIfCompleted();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------
  // Realtime: ride status
  void _subscribeRideStatus() {
    _rideChannel =
        supabase.channel('ride_requests_${widget.rideId}')
          ..onPostgresChanges(
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

              final st = (updated['status'] ?? '').toString();
              _syncPublisherToStatus(st);

              await _notify('Ride Update', 'Status is now $st');

              if (st == 'en_route') setState(() => _followDriver = true);

              await _maybePromptRatingIfCompleted();
            },
          )
          ..subscribe();
  }

  void _syncPublisherToStatus(String status) {
    // start sending when accepted/en_route, stop otherwise
    if (status == 'accepted' || status == 'en_route') {
      _publisher.start(); // safe/idempotent
      _ensurePollingFallback();
    } else if (status == 'completed' ||
        status == 'cancelled' ||
        status == 'canceled') {
      _publisher.stop();
      _pollFallback?.cancel();
    }
  }

  void _ensurePollingFallback() {
    _pollFallback?.cancel();
    _pollFallback = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        // prefer ride_id + actor row
        final last =
            await supabase
                .from('live_locations')
                .select('lat,lng,heading,updated_at')
                .eq('ride_id', widget.rideId)
                .eq('actor', 'driver')
                .maybeSingle();
        if (last != null) {
          _consumeDriverLocation(last as Map);
        }
      } catch (_) {}
    });
  }

  // -------------------------------------------------
  // Realtime: live driver (listen to our own published updates)
  void _subscribeDriverLive(String rideId) {
    _driverLiveChannel =
        supabase.channel('live_locations_driver:$rideId')
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.insert,
            callback: (p) {
              final rec = p.newRecord;
              if (rec['ride_id']?.toString() != rideId) return;
              if (rec['actor']?.toString() != 'driver') return;
              _consumeDriverLocation(rec);
            },
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.update,
            callback: (p) {
              final rec = p.newRecord;
              if (rec['ride_id']?.toString() != rideId) return;
              if (rec['actor']?.toString() != 'driver') return;
              _consumeDriverLocation(rec);
            },
          )
          ..subscribe();
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

    final status = (_ride?['status'] ?? '').toString();
    if (_followDriver && status == 'en_route') {
      final z = _mapReady ? _map.camera.zoom : 15.0;
      _safeMove(p, z.clamp(14, 16));
    }
  }

  // -------------------------------------------------
  // Realtime: passenger live (optional)
  void _subscribePassengerLive(String passengerUserId) {
    _passengerLiveChannel =
        supabase.channel('live_locations_passenger_$passengerUserId')
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.update,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: passengerUserId,
            ),
            callback: (payload) {
              final rec = payload.newRecord;
              final lat = (rec['lat'] as num?)?.toDouble();
              final lng = (rec['lng'] as num?)?.toDouble();
              if (lat == null || lng == null) return;
              setState(() => _passengerLive = LatLng(lat, lng));
            },
          )
          ..subscribe();
  }

  // -------------------------------------------------
  // Ratings
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

  // -------------------------------------------------
  // BUILD
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

    // Driver marker position pref: live interp > next > pickup
    final driverPoint = _driverInterp ?? _driverNext ?? pickup;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Driver Ride Details'),
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
                // Route overview
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
                        label: null,
                      ),
                    ),
                    // Passenger: live or pickup
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
                    // Passenger row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage:
                              (_passenger?['avatar_url'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? NetworkImage(
                                    _passenger!['avatar_url'] as String,
                                  )
                                  : null,
                          child:
                              ((_passenger?['avatar_url'] as String?)
                                          ?.isEmpty ??
                                      true)
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
                                  if (passengerId != null)
                                    InkWell(
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          builder:
                                              (_) => RatingDetailsSheet(
                                                userId: passengerId,
                                                title: 'Passenger feedback',
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
                        TextButton.icon(
                          onPressed: () => _safeMove(dest, 15),
                          icon: const Icon(Icons.place, size: 16),
                          label: const Text('Destination'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

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

  // UI helpers
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
}

// small extension to remove channels cleanly
extension on RealtimeChannel {
  void kill(SupabaseClient sb) => sb.removeChannel(this);
}
