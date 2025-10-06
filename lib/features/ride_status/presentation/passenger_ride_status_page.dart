// lib/features/ride_status/presentation/passenger_ride_status_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Chat / Verify / Ratings / Payments
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/payments/presentation/payment_status_chip.dart';

// Live tracking
import 'package:godavao/features/live_tracking/data/live_publisher.dart';
import 'package:godavao/features/live_tracking/data/live_subscriber.dart';

// Fare calc
import 'package:godavao/core/fare_service.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String rideId;
  const PassengerRideStatusPage({super.key, required this.rideId});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  final _map = MapController();

  Map<String, dynamic>? _ride; // merged from RPC
  Map<String, dynamic>? _payment;

  bool _loading = true;
  String? _error;
  bool _ratingPromptShown = false;

  // parent watchers
  StreamSubscription<List<Map<String, dynamic>>>? _rideReqSub;
  StreamSubscription<List<Map<String, dynamic>>>? _rideMatchSub;

  // chat
  String? _matchId;

  // live tracking
  LivePublisher? _publisher; // publish passenger
  LiveSubscriber? _driverSub; // follow driver
  LiveSubscriber? _selfSub; // (optional) mirror passenger point
  LatLng? _driverLive;
  LatLng? _myLive;

  // camera / UX
  bool _didFitOnce = false;

  // fare
  final FareService _fareService = FareService();
  FareBreakdown? _fareBx;
  bool _estimatingFare = false;
  double _platformFeeRate = 0.0;
  RealtimeChannel? _feeChannel;

  static const _bg = Color(0xFFF7F7FB);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rideReqSub?.cancel();
    _rideMatchSub?.cancel();
    _driverSub?.dispose();
    _selfSub?.dispose();
    _publisher?.stop();
    if (_feeChannel != null) _sb.removeChannel(_feeChannel!);
    super.dispose();
  }

  /* ───────────────────────── Lifecycle ───────────────────────── */

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only publish passenger location while the app is foregrounded & ride active
    if (state == AppLifecycleState.resumed) {
      _syncPassengerPublisherToStatus();
    } else if (state == AppLifecycleState.paused) {
      if (!(_status == 'accepted' || _status == 'en_route')) {
        _publisher?.stop();
      }
    }
  }

  /* ───────────────────────── Bootstrap ───────────────────────── */

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _didFitOnce = false;
    });

    try {
      await Future.wait([
        _loadRideComposite(),
        _loadPayment(),
        _loadMatchId(),
        _loadPlatformFeeRate(),
      ]);
      _subscribePlatformFee();
      _watchParents();
      _syncPassengerPublisherToStatus();
      _startDriverSubscriber();
      _startSelfSubscriber();
      await _estimateFare();
      await _maybePromptRatingIfCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRideComposite() async {
    final res =
        await _sb
            .rpc('passenger_ride_by_id', params: {'p_ride_id': widget.rideId})
            .select()
            .single();
    if (!mounted) return;
    setState(() => _ride = (res as Map).cast<String, dynamic>());
  }

  Future<void> _loadPayment() async {
    final res =
        await _sb
            .from('payment_intents')
            .select('ride_id, status, amount')
            .eq('ride_id', widget.rideId)
            .maybeSingle();
    if (!mounted) return;
    setState(() => _payment = (res as Map?)?.cast<String, dynamic>());
  }

  Future<void> _loadMatchId() async {
    final row =
        await _sb
            .from('ride_matches')
            .select('id')
            .eq('ride_request_id', widget.rideId)
            .maybeSingle();
    if (!mounted) return;
    setState(() => _matchId = (row as Map?)?['id']?.toString());
  }

  void _watchParents() {
    _rideReqSub?.cancel();
    _rideReqSub = _sb
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', widget.rideId)
        .listen((_) async {
          await _loadRideComposite();
          await _loadPayment();
          await _loadMatchId();
          _syncPassengerPublisherToStatus();
          await _estimateFare();
          await _maybePromptRatingIfCompleted();
          if (mounted) setState(() {});
        });

    _rideMatchSub?.cancel();
    _rideMatchSub = _sb
        .from('ride_matches')
        .stream(primaryKey: ['id'])
        .eq('ride_request_id', widget.rideId)
        .listen((_) async {
          await _loadRideComposite();
          await _loadPayment();
          await _loadMatchId();
          _syncPassengerPublisherToStatus();
          await _estimateFare();
          await _maybePromptRatingIfCompleted();
          if (mounted) setState(() {});
        });
  }

  /* ───────────────────── Platform fee + Fare ─────────────────── */

  Future<void> _loadPlatformFeeRate() async {
    try {
      final row =
          await _sb
              .from('app_settings')
              .select('key, value, value_num')
              .eq('key', 'platform_fee_rate')
              .maybeSingle();

      final num? n = (row?['value_num'] as num?) ?? (row?['value'] as num?);
      final parsed =
          n?.toDouble() ?? double.tryParse(row?['value']?.toString() ?? '');
      if (parsed != null && parsed >= 0 && parsed <= 1) {
        if (!mounted) return;
        setState(() => _platformFeeRate = parsed);
      }
    } catch (_) {
      /* keep default */
    }
  }

  void _subscribePlatformFee() {
    if (_feeChannel != null) return;
    _feeChannel =
        _sb.channel('app_settings:platform_fee_rate:view')
          ..onPostgresChanges(
            schema: 'public',
            table: 'app_settings',
            event: PostgresChangeEvent.insert,
            callback: (p) {
              final rec = p.newRecord as Map?;
              if (rec?['key']?.toString() != 'platform_fee_rate') return;
              final num? n =
                  (rec?['value_num'] as num?) ?? (rec?['value'] as num?);
              final parsed =
                  n?.toDouble() ??
                  double.tryParse(rec?['value']?.toString() ?? '');
              if (parsed != null && parsed >= 0 && parsed <= 1) {
                if (!mounted) return;
                setState(() => _platformFeeRate = parsed);
                _estimateFare();
              }
            },
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'app_settings',
            event: PostgresChangeEvent.update,
            callback: (p) {
              final rec = p.newRecord as Map?;
              if (rec?['key']?.toString() != 'platform_fee_rate') return;
              final num? n =
                  (rec?['value_num'] as num?) ?? (rec?['value'] as num?);
              final parsed =
                  n?.toDouble() ??
                  double.tryParse(rec?['value']?.toString() ?? '');
              if (parsed != null && parsed >= 0 && parsed <= 1) {
                if (!mounted) return;
                setState(() => _platformFeeRate = parsed);
                _estimateFare();
              }
            },
          )
          ..subscribe();
  }

  Future<void> _estimateFare() async {
    final p = _pickup;
    final d = _dropoff;
    if (p == null || d == null) return;

    final seats = (_ride?['requested_seats'] as int?) ?? 1;
    // server-provided current rider count if available (includes unique riders)
    final carpoolPassengers = (_ride?['passenger_count'] as int?) ?? seats;
    final surge = (_ride?['surge_multiplier'] as num?)?.toDouble() ?? 1.0;

    setState(() => _estimatingFare = true);
    try {
      final bx = await _fareService.estimate(
        pickup: p,
        destination: d,
        seats: seats,
        carpoolPassengers: carpoolPassengers,
        platformFeeRate: _platformFeeRate,
        surgeMultiplier: surge,
      );
      if (!mounted) return;
      setState(() => _fareBx = bx);
    } catch (_) {
      /* ignore */
    } finally {
      if (mounted) setState(() => _estimatingFare = false);
    }
  }

  /* ───────────────────── Live tracking glue ──────────────────── */

  void _syncPassengerPublisherToStatus() {
    final s = _status;
    if (s == 'accepted' || s == 'en_route') {
      _publisher ??= LivePublisher(
        _sb,
        userId: _sb.auth.currentUser!.id,
        rideId: widget.rideId,
        actor: 'passenger',
        minMeters: 8,
        minHeadingDelta: 10,
        minPeriod: const Duration(seconds: 3),
        distanceFilter: 3,
      );
      if (!(_publisher!.isRunning)) {
        _publisher!.start();
      }
    } else {
      _publisher?.stop();
    }
  }

  void _startDriverSubscriber() {
    _driverSub?.dispose();
    _driverSub = LiveSubscriber(
      _sb,
      rideId: widget.rideId,
      actor: 'driver',
      onUpdate: (pos, heading) {
        if (!mounted) return;

        final prev = _driverLive;
        if (prev != null &&
            prev.latitude == pos.latitude &&
            prev.longitude == pos.longitude) {
          return;
        }
        setState(() => _driverLive = pos);

        if (!_didFitOnce) {
          _didFitOnce = true;
          _fitImportant();
        }
      },
    )..listen();
  }

  void _startSelfSubscriber() {
    _selfSub?.dispose();
    _selfSub = LiveSubscriber(
      _sb,
      rideId: widget.rideId,
      actor: 'passenger',
      onUpdate: (pos, heading) {
        if (!mounted) return;

        final prev = _myLive;
        if (prev != null &&
            prev.latitude == pos.latitude &&
            prev.longitude == pos.longitude) {
          return;
        }
        setState(() => _myLive = pos);

        if (!_didFitOnce && _driverLive != null) {
          _didFitOnce = true;
          _fitImportant();
        }
      },
    )..listen();
  }

  void _fitImportant() {
    final pts = <LatLng>[
      if (_pickup != null) _pickup!,
      if (_dropoff != null) _dropoff!,
      if (_driverLive != null) _driverLive!,
      if (_myLive != null) _myLive!,
    ];
    if (pts.length < 2) return;
    final bounds = LatLngBounds.fromPoints(pts);
    _map.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36)),
    );
  }

  /* ───────────────────────── Helpers ───────────────────────── */

  String get _status =>
      (_ride?['effective_status'] as String?)?.toLowerCase() ??
      (_ride?['status'] as String?)?.toLowerCase() ??
      'pending';

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
      case 'canceled':
      case 'declined':
        return Colors.red;
      default:
        return Colors.black87;
    }
  }

  LatLng? get _pickup {
    final lat = _ride?['pickup_lat'] as num?;
    final lng = _ride?['pickup_lng'] as num?;
    if (lat == null || lng == null) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  LatLng? get _dropoff {
    final lat = _ride?['destination_lat'] as num?;
    final lng = _ride?['destination_lng'] as num?;
    if (lat == null || lng == null) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  String _peso(num? v) =>
      v == null ? '₱0.00' : '₱${(v.toDouble()).toStringAsFixed(2)}';

  Future<void> _cancelRide() async {
    try {
      await _sb
          .from('ride_requests')
          .update({'status': 'canceled'})
          .eq('id', widget.rideId);
      await _sb
          .from('payment_intents')
          .update({'status': 'canceled'})
          .eq('ride_id', widget.rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ride canceled')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    }
  }

  Future<void> _maybePromptRatingIfCompleted() async {
    if (_ratingPromptShown || _status != 'completed') return;
    final me = _sb.auth.currentUser?.id;
    final driverId = _ride?['driver_id']?.toString();
    if (me == null || driverId == null) return;

    final existing = await RatingsService(_sb).getExistingRating(
      rideId: widget.rideId,
      raterUserId: me,
      rateeUserId: driverId,
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
            rateeUserId: driverId,
            rateeName: (_ride?['driver_name']?.toString() ?? 'Driver'),
            rateeRole: 'driver',
          ),
    );
  }

  /* ───────────────────────── UI ───────────────────────── */

  @override
  Widget build(BuildContext context) {
    final fare = (_ride?['fare'] as num?)?.toDouble();
    final passengerId = _ride?['passenger_id']?.toString();
    final driverId = _ride?['driver_id']?.toString();
    final driverName = (_ride?['driver_name'] as String?) ?? '—';
    final seatsReq = (_ride?['requested_seats'] as int?) ?? 1;
    final bookingType = (_ride?['booking_type'] as String?) ?? 'shared';
    final currentCarpool =
        (_ride?['passenger_count'] as int?) ??
        1; // server-populated count of unique riders

    final center =
        _driverLive ??
        _pickup ??
        _dropoff ??
        const LatLng(7.1907, 125.4553); // fallback (Davao)

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Ride Status'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        actions: [
          if (driverId != null) VerifiedBadge(userId: driverId, size: 22),
          if (driverId != null && _matchId != null)
            IconButton(
              tooltip: 'Chat with driver',
              icon: const Icon(Icons.message_outlined),
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
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                onRefresh: () async {
                  _didFitOnce = false;
                  await _loadRideComposite();
                  await _loadPayment();
                  await _loadMatchId();
                  await _loadPlatformFeeRate();
                  _syncPassengerPublisherToStatus();
                  await _estimateFare();
                  await _maybePromptRatingIfCompleted();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    // Status & chips
                    _SectionCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Chip(
                            icon: Icons.info_outline,
                            label: _status.toUpperCase(),
                            color: _statusColor(_status).withOpacity(.10),
                            textColor: _statusColor(_status),
                          ),
                          if (fare != null)
                            _Chip(
                              icon: Icons.payments_outlined,
                              label: _peso(fare),
                            ),
                          if (_payment != null)
                            PaymentStatusChip(
                              status: _payment!['status'] as String?,
                              amount: (_payment!['amount'] as num?)?.toDouble(),
                            ),
                          _Chip(
                            icon: Icons.event_seat_outlined,
                            label: seatsReq > 1 ? '$seatsReq seats' : '1 seat',
                          ),
                          _Chip(
                            icon: Icons.groups_2_outlined,
                            label: 'Riders: $currentCarpool',
                          ),
                          _Chip(
                            icon: Icons.group_outlined,
                            label: 'Booking: ${bookingType.toUpperCase()}',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Map card
                    _SectionCard(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 260,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: FlutterMap(
                                mapController: _map,
                                options: MapOptions(center: center, zoom: 13),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.godavao.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      if (_pickup != null)
                                        Marker(
                                          point: _pickup!,
                                          width: 30,
                                          height: 30,
                                          child: const Icon(
                                            Icons.place,
                                            color: Colors.green,
                                            size: 28,
                                          ),
                                        ),
                                      if (_dropoff != null)
                                        Marker(
                                          point: _dropoff!,
                                          width: 30,
                                          height: 30,
                                          child: const Icon(
                                            Icons.flag,
                                            color: Colors.red,
                                            size: 26,
                                          ),
                                        ),
                                      if (_driverLive != null)
                                        Marker(
                                          point: _driverLive!,
                                          width: 36,
                                          height: 36,
                                          child: const Icon(
                                            Icons.directions_car,
                                            size: 30,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      if (_myLive != null)
                                        Marker(
                                          point: _myLive!,
                                          width: 32,
                                          height: 32,
                                          child: const Icon(
                                            Icons.person_pin_circle,
                                            size: 28,
                                            color: Colors.deepPurple,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _MiniAction(
                                icon: Icons.center_focus_strong,
                                label: 'Driver',
                                onTap: () {
                                  if (_driverLive != null) {
                                    _map.move(_driverLive!, 16);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _MiniAction(
                                icon: Icons.place_outlined,
                                label: 'Pickup',
                                onTap: () {
                                  if (_pickup != null) {
                                    _map.move(_pickup!, 16);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _MiniAction(
                                icon: Icons.flag_outlined,
                                label: 'Dropoff',
                                onTap: () {
                                  if (_dropoff != null) {
                                    _map.move(_dropoff!, 16);
                                  }
                                },
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _fitImportant,
                                icon: const Icon(Icons.fullscreen),
                                label: const Text('Fit'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Driver info
                    _SectionCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_car_outlined,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverId == null
                                      ? 'Waiting for driver'
                                      : driverName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  driverId == null
                                      ? 'We’ll notify you when a driver is matched'
                                      : 'Your driver',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (driverId != null)
                            UserRatingBadge(userId: driverId, iconSize: 18),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Fare breakdown
                    if (_fareBx != null)
                      _SectionCard(
                        child: _FareBreakdownPro(
                          bx: _fareBx!,
                          peso: _peso,
                          estimating: _estimatingFare,
                        ),
                      )
                    else if (fare != null)
                      _SectionCard(
                        child: _FareBreakdownSimple(
                          total: fare,
                          seats: seatsReq,
                          bookingType: bookingType,
                          peso: _peso,
                        ),
                      ),

                    // NEW: Carpool breakdown preview (uses fare rules & current distance/time)
                    if (_fareBx != null) ...[
                      const SizedBox(height: 12),
                      _SectionCard(
                        child: _CarpoolBreakdownTable(
                          currentCarpool: currentCarpool,
                          seatsRequested: seatsReq,
                          bx: _fareBx!,
                          fareService: _fareService,
                          peso: _peso,
                        ),
                      ),
                    ],

                    // Rating CTA
                    if (_status == 'completed' && driverId != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.star),
                        label: const Text('Rate your driver'),
                        onPressed: _maybePromptRatingIfCompleted,
                      ),
                    ],
                  ],
                ),
              ),
      bottomNavigationBar: _buildBottomBar(
        passengerId ?? 'You',
        driverName,
        (_ride?['fare'] as num?)?.toDouble(),
      ),
    );
  }

  Widget _buildBottomBar(String passenger, String driverName, double? fare) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.info_outline),
                label: const Text('Details'),
                onPressed:
                    () => _openDetailsSheet(
                      context: context,
                      passengerName: passenger,
                      driverName: driverName,
                      fare: fare,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: Icon(
                  _status == 'en_route'
                      ? Icons.emergency_share
                      : Icons.cancel_outlined,
                ),
                label: Text(
                  _status == 'en_route'
                      ? 'SOS'
                      : (_status == 'pending' || _status == 'accepted')
                      ? 'Cancel ride'
                      : 'Close',
                ),
                onPressed: () {
                  if (_status == 'en_route') {
                    _showSosDialog();
                  } else if (_status == 'pending' || _status == 'accepted') {
                    _cancelRide();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetailsSheet({
    required BuildContext context,
    required String passengerName,
    required String driverName,
    double? fare,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Ride ID', widget.rideId),
              const SizedBox(height: 6),
              _detailRow('Status', _status.toUpperCase()),
              const Divider(height: 20),
              _detailRow('Passenger', passengerName),
              _detailRow('Driver', driverName),
              if (fare != null) _detailRow('Fare', _peso(fare)),
              const SizedBox(height: 12),
              if (_payment != null)
                PaymentStatusChip(
                  status: _payment!['status'] as String?,
                  amount: (_payment!['amount'] as num?)?.toDouble(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showSosDialog() {
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Emergency'),
            content: const Text(
              'Do you want to trigger SOS and share your live location with your emergency contacts?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.emergency_share),
                label: const Text('Trigger SOS'),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SOS triggered')),
                  );
                  // Hook your SOS flow here
                },
              ),
            ],
          ),
    );
  }
}

/* -------------------- UI bits -------------------- */

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _SectionCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12.withOpacity(.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _FareBreakdownSimple extends StatelessWidget {
  final double total;
  final int seats;
  final String bookingType; // shared | pakyaw
  final String Function(num?) peso;

  const _FareBreakdownSimple({
    required this.total,
    required this.seats,
    required this.bookingType,
    required this.peso,
  });

  @override
  Widget build(BuildContext context) {
    final perSeat = seats > 0 ? (total / seats) : total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fare Breakdown',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        _row('Booking type', bookingType.toUpperCase()),
        _row('Seats', '$seats'),
        const SizedBox(height: 6),
        _row('Per seat', peso(perSeat)),
        const Divider(height: 18),
        _row('Total', peso(total), bold: true),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FareBreakdownPro extends StatelessWidget {
  final FareBreakdown bx;
  final String Function(num?) peso;
  final bool estimating;
  const _FareBreakdownPro({
    required this.bx,
    required this.peso,
    this.estimating = false,
  });

  @override
  Widget build(BuildContext context) {
    final perSeat = bx.seatsBilled > 0 ? (bx.total / bx.seatsBilled) : bx.total;

    TextStyle label = const TextStyle(color: Colors.black54, fontSize: 13);
    TextStyle val = const TextStyle(fontWeight: FontWeight.w700);
    TextStyle valStrong = const TextStyle(fontWeight: FontWeight.w800);

    Widget row(String l, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(l, style: label)),
          Text(v, style: strong ? valStrong : val),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Fare Breakdown',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (estimating) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Trip metrics
        Row(
          children: [
            Expanded(
              child: row('Distance', '${bx.distanceKm.toStringAsFixed(2)} km'),
            ),
            Expanded(
              child: row('Time', '${bx.durationMin.toStringAsFixed(0)} min'),
            ),
          ],
        ),
        const SizedBox(height: 6),

        row('Seats billed', '${bx.seatsBilled}'),
        row(
          'Carpool discount',
          '${(bx.carpoolDiscountPct * 100).toStringAsFixed(0)}%',
        ),
        row('Night surcharge', peso(bx.nightSurcharge)),
        row('Surge used', '${bx.surgeMultiplier.toStringAsFixed(2)}×'),

        const Divider(height: 18),

        row('Subtotal', peso(bx.subtotal)),
        row('Per seat (approx.)', peso(perSeat)),
        row('Platform fee', '- ${peso(bx.platformFee)}'),
        const Divider(height: 18),
        row('Driver take (est.)', peso(bx.driverTake)),
        row('Total', peso(bx.total), strong: true),
      ],
    );
  }
}

/// NEW: Carpool breakdown table (1..N riders)
class _CarpoolBreakdownTable extends StatelessWidget {
  final int currentCarpool;
  final int seatsRequested;
  final FareBreakdown bx;
  final FareService fareService;
  final String Function(num?) peso;

  const _CarpoolBreakdownTable({
    required this.currentCarpool,
    required this.seatsRequested,
    required this.bx,
    required this.fareService,
    required this.peso,
  });

  @override
  Widget build(BuildContext context) {
    // Build rider counts from rules (keys) + ensure "1" is included
    final keys =
        <int>{1, ...fareService.rules.carpoolDiscountByPax.keys}.toList()
          ..sort();

    final rows = <TableRow>[];
    for (final pax in keys) {
      final fb = fareService.estimateForDistance(
        distanceKm: bx.distanceKm,
        durationMin: bx.durationMin,
        seats: seatsRequested,
        carpoolPassengers: pax,
        platformFeeRate: fareService.rules.defaultPlatformFeeRate,
        surgeMultiplier: bx.surgeMultiplier,
      );
      final perSeat =
          fb.seatsBilled > 0 ? (fb.total / fb.seatsBilled) : fb.total;

      final isCurrent = pax == currentCarpool;
      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: isCurrent ? Colors.indigo.withOpacity(.05) : null,
          ),
          children: [
            _cell('$pax', bold: isCurrent),
            _cell(
              '${(fb.carpoolDiscountPct * 100).toStringAsFixed(0)}%',
              mono: true,
              bold: isCurrent,
            ),
            _cell(peso(fb.total), mono: true, bold: isCurrent),
            _cell(peso(perSeat), mono: true, bold: isCurrent),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardTitle(
          icon: Icons.groups_2_outlined,
          text: 'Carpool Breakdown',
        ),
        const SizedBox(height: 6),
        Text(
          'How your fare changes with the number of riders sharing this route. '
          'Current riders highlighted.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.0),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.6),
            3: FlexColumnWidth(1.6),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade100),
              children: const [
                _TH('Riders'),
                _TH('Discount'),
                _TH('Total (₱)'),
                _TH('Per seat (₱)'),
              ],
            ),
            ...rows,
          ],
        ),
      ],
    );
  }

  static Widget _cell(String t, {bool mono = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          fontFamily: mono ? 'monospace' : null,
        ),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String t;
  const _TH(this.t, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(
        t,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Color? textColor;
  const _Chip({
    required this.icon,
    required this.label,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: textColor ?? Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CardTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6A27F7)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ],
    );
  }
}
