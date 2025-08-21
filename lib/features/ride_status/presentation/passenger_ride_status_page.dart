import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/features/payments/presentation/gcash_proof_sheet.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/presentation/rating_details_sheet.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/safety/presentation/sos_sheet.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String rideId;
  const PassengerRideStatusPage({required this.rideId, super.key});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _rideChannel;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _ride;
  String? _matchId;

  // Driver identity (for rating + display)
  String? _driverId;
  Map<String, dynamic>? _driverAggregate; // {avg_rating, rating_count}
  bool _fetchingDriverAgg = false;

  // Avoid duplicate rating modals
  bool _ratingPromptShown = false;

  // Theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    _loadRideDetails();
    _subscribeToRideUpdates();
  }

  Future<void> _loadRideDetails() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Load the ride_request
      final rideResp =
          await _supabase
              .from('ride_requests')
              .select('''
            id,
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng,
            status,
            fare,
            payment_method,
            driver_route_id
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (rideResp == null) {
        throw Exception('Ride not found');
      }
      _ride = (rideResp as Map).cast<String, dynamic>();

      // 2) Load the matching ride_matches row
      final matchResp =
          await _supabase
              .from('ride_matches')
              .select('id')
              .eq('ride_request_id', widget.rideId)
              .maybeSingle();

      if (matchResp == null) {
        throw Exception('No match found for this ride');
      }
      _matchId = (matchResp as Map)['id']?.toString();

      // 3) Resolve driver_id from driver_routes (if assigned)
      await _resolveDriverIdAndAgg();

      // 4) If already completed when user opens page, maybe prompt rating
      await _maybePromptRatingIfCompleted();
    } on PostgrestException catch (e) {
      _error = 'Supabase error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _resolveDriverIdAndAgg() async {
    final driverRouteId = _ride?['driver_route_id'];
    if (driverRouteId == null) return;

    final dr =
        await _supabase
            .from('driver_routes')
            .select('driver_id')
            .eq('id', driverRouteId)
            .maybeSingle();

    if (dr != null) {
      _driverId = (dr as Map)['driver_id']?.toString();
      if (_driverId != null) {
        await _fetchDriverAggregate(); // best-effort
      }
    }
  }

  Future<void> _fetchDriverAggregate() async {
    if (_driverId == null) return;
    if (!mounted) return;
    setState(() {
      _fetchingDriverAgg = true;
    });
    try {
      final service = RatingsService(_supabase);
      final agg = await service.fetchUserAggregate(_driverId!);
      if (!mounted) return;
      setState(() {
        _driverAggregate = agg;
      });
    } catch (_) {
      // ignore; show nothing if not present
    } finally {
      if (mounted) {
        setState(() {
          _fetchingDriverAgg = false;
        });
      }
    }
  }

  void _subscribeToRideUpdates() {
    // Subscribe to ride_requests updates and filter inside callback
    _rideChannel =
        _supabase
            .channel('ride_requests:${widget.rideId}')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_requests',
              event: PostgresChangeEvent.update,
              callback: (payload) async {
                final newRec = payload.newRecord;
                if (newRec == null) return;
                final updated = (newRec as Map).cast<String, dynamic>();
                if (updated['id'] != widget.rideId) return;

                if (!mounted) return;
                setState(() {
                  _ride = updated;
                });

                // Small toast note
                if (mounted) {
                  final st = updated['status'];
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ride status: $st'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }

                // Re-resolve driver_id if assignment changed
                await _resolveDriverIdAndAgg();

                // If completed, maybe show rating sheet
                await _maybePromptRatingIfCompleted();
              },
            )
            .subscribe();
  }

  Future<void> _maybePromptRatingIfCompleted() async {
    if (_ratingPromptShown) return;
    final status = _ride?['status']?.toString();
    if (status != 'completed') return;

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (_driverId == null) return;

    // Check if a rating already exists (passenger → driver for this ride)
    final service = RatingsService(_supabase);
    final existing = await service.getExistingRating(
      rideId: widget.rideId,
      raterUserId: uid,
      rateeUserId: _driverId!,
    );
    if (existing != null) return;

    // Show sheet (passenger rates driver)
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

  @override
  void dispose() {
    if (_rideChannel != null) {
      _supabase.removeChannel(_rideChannel!);
    }
    super.dispose();
  }

  // ---------- UI helpers ----------

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

    final driverRatingText = () {
      if (_fetchingDriverAgg) return 'Loading…';
      final avg = (_driverAggregate?['avg_rating'] as num?)?.toDouble();
      final cnt = (_driverAggregate?['rating_count'] as int?) ?? 0;
      if (avg == null) return 'No ratings yet';
      return '${avg.toStringAsFixed(2)} ★  ($cnt)';
    }();

    final status = (r['status'] as String?) ?? 'pending';
    final fare = (r['fare'] as num?)?.toDouble() ?? 0.0;

    final canUploadGcash =
        (status == 'accepted' ||
            status == 'en_route' ||
            status == 'completed') &&
        (r['payment_method'] == 'gcash');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Ride Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
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
          // Map canvas
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
                      strokeWidth: 4,
                      color: _purple,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 38,
                      height: 38,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 38,
                      ),
                    ),
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

          // Bottom sheet summary card (sticky)
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
                    // Header row: Driver + status pill
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
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

                    // Rating block
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

                    // Fare row
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
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Actions
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

                    if (status == 'completed' && _driverId != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.star),
                          label: const Text('Rate your driver'),
                          onPressed: () async {
                            await _maybePromptRatingIfCompleted();
                          },
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
