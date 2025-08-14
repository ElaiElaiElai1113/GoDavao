import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';

// ⬇️ Add this import for the compact stars
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
            driver_route_id
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (rideResp == null) {
        throw Exception('Ride not found');
      }
      _ride = Map<String, dynamic>.from(rideResp as Map);

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
      _matchId = (matchResp as Map)['id'] as String;

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

    // Fetch driver_id from driver_routes
    final dr =
        await _supabase
            .from('driver_routes')
            .select('driver_id')
            .eq('id', driverRouteId)
            .maybeSingle();

    if (dr != null) {
      _driverId = (dr as Map)['driver_id']?.toString();
      if (_driverId != null) {
        await _fetchDriverAggregate(); // best-effort, ignore errors
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
    // keep subscription alive to auto-refresh status
    _rideChannel =
        _supabase
            .channel('ride_requests:${widget.rideId}')
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
                setState(() {
                  _ride = updated;
                });

                // Small toast note
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ride status: ${updated['status']}'),
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
    final pickup = LatLng(r['pickup_lat'], r['pickup_lng']);
    final dest = LatLng(r['destination_lat'], r['destination_lng']);

    // Keeping your previous text fallback if you need it elsewhere
    final driverRatingText = () {
      if (_fetchingDriverAgg) return 'Loading…';
      final avg = (_driverAggregate?['avg_rating'] as num?)?.toDouble();
      final cnt = (_driverAggregate?['rating_count'] as int?) ?? 0;
      if (avg == null) return 'No ratings yet';
      return '${avg.toStringAsFixed(2)} ★  ($cnt)';
    }();

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Details')),
      body: Column(
        children: [
          // Header with inline badge beside "Driver"
          ListTile(
            title: Row(
              children: [
                Expanded(child: Text('Driver: ${_driverId ?? 'unassigned'}')),
                if (_driverId != null)
                  UserRatingBadge(userId: _driverId!, iconSize: 14),
              ],
            ),
            subtitle: Text('Status: ${r['status']}'),
          ),

          // map view
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: pickup, zoom: 13),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.godavao',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, dest],
                      strokeWidth: 4,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                    Marker(
                      point: dest,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                if (r['status'] == 'completed' && _driverId != null)
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
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.message),
                  label: const Text('Chat with Driver'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
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
          ),
        ],
      ),
    );
  }
}
