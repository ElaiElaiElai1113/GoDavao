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

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, super.key});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  Map<String, dynamic>? _ride; // ride_requests row
  Map<String, dynamic>? _passenger; // users row (best-effort)
  bool _loading = true;
  String? _error;

  bool _ratingPromptShown = false;

  // Brand tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _loadRide();
    _subscribeToUpdates();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
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
            passenger_id
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
      }

      await _maybePromptRatingIfCompleted();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _subscribeToUpdates() {
    _channel =
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

                await _maybePromptRatingIfCompleted();
              },
            )
            .subscribe();
  }

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
    final pickup = LatLng(r['pickup_lat'], r['pickup_lng']);
    final dest = LatLng(r['destination_lat'], r['destination_lng']);
    final status = (r['status'] ?? '').toString();

    final passengerName = (_passenger?['name'] as String?) ?? 'Passenger';
    final passengerId = r['passenger_id']?.toString();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('Driver Ride Details')),
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
              options: MapOptions(center: pickup, zoom: 13),
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
                    Marker(
                      point: pickup,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.green,
                        size: 36,
                      ),
                    ),
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
                                    child: Row(
                                      children: const [
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
