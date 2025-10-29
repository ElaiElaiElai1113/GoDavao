// lib/features/ride_status/presentation/passenger_ride_status_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Features
import 'package:godavao/features/chat/presentation/chat_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rate_user.dart';
import 'package:godavao/features/ratings/data/ratings_service.dart';
import 'package:godavao/features/payments/presentation/payment_status_chip.dart';
import 'package:godavao/features/safety/presentation/sos_sheet.dart'; // <-- Safety

// Live tracking
import 'package:godavao/features/live_tracking/data/live_publisher.dart';
import 'package:godavao/features/live_tracking/data/live_subscriber.dart';

// Pricing
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
  // Core
  final _sb = Supabase.instance.client;
  final _map = MapController();
  bool get _isChatLocked {
  final s = _status.toLowerCase();
  return s == 'cancelled' || s == 'canceled' || s == 'declined' || s == 'completed';
}

  // Data
  Map<String, dynamic>? _ride; // passenger_ride_by_id composite
  Map<String, dynamic>? _payment; // payment_intents row (maybe null)
  String? _passengerNote;

  // Live state
  LivePublisher? _publisher; // this passenger's publisher
  LiveSubscriber? _driverSub;
  LiveSubscriber? _selfSub;
  LatLng? _driverLive;
  LatLng? _myLive;

  // Streams
  StreamSubscription<List<Map<String, dynamic>>>? _rideReqSub;
  StreamSubscription<List<Map<String, dynamic>>>? _rideMatchSub;
  RealtimeChannel? _feeChannel;

  // IDs / booking facts
  String? _matchId;
  int _seatsBilled = 1; // ride_matches.seats_allocated for THIS booking

  // Carpool snapshot across the route
  int _activeBookings = 1; // unique active ride requests
  int _activeSeatsTotal = 1; // sum of seats across those bookings

  // Fare
  final FareService _fareService = FareService(
    rules: const FareRules(
      defaultPlatformFeeRate: 0.15,
      carpoolDiscountByPax: {2: 0.06, 3: 0.12, 4: 0.20, 5: 0.25},
    ),
  );
  FareBreakdown? _fareBx;
  double _platformFeeRate = 0.0;
  bool _estimatingFare = false;

  // UX state
  bool _loading = true;
  String? _error;
  bool _ratingPromptShown = false;
  bool _didFitOnce = false;

  // Theme
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  // ───────────────────────── Lifecycle ─────────────────────────

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPassengerPublisherToStatus();
    } else if (state == AppLifecycleState.paused) {
      if (!(_status == 'accepted' || _status == 'en_route')) {
        _publisher?.stop();
      }
    }
  }

  // ───────────────────────── Bootstrap ─────────────────────────

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _didFitOnce = false;
    });

    try {
      await Future.wait([
        _loadPassengerNoteOnly(),
        _loadRideComposite(),
        _loadPayment(),
        _loadMatchFacts(), // loads _matchId + _seatsBilled
        _loadPlatformFeeRate(),
      ]);

      await _loadCarpoolSeatSnapshot(); // riders vs seats on the route

      _subscribePlatformFee();
      _watchParents();

      _syncPassengerPublisherToStatus();
      _startDriverSubscriber();
      _startSelfSubscriber();

      await _estimateFare();
      await _maybePromptRatingIfCompleted();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────────────────── DB Loads ─────────────────────────

  Future<void> _loadRideComposite() async {
  final res = await _sb
      .rpc('passenger_ride_by_id', params: {'p_ride_id': widget.rideId})
      .select()
      .single();

  if (!mounted) return;

  final m = (res as Map).cast<String, dynamic>();
  setState(() {
    _ride = m;
    _passengerNote = (m['passenger_note'] as String?); // 👈 try from RPC
  });

  // If the RPC doesn’t include passenger_note yet, do a quick fallback fetch.
  if (_passengerNote == null) {
    final rr = await _sb
        .from('ride_requests')
        .select('passenger_note')
        .eq('id', widget.rideId)
        .maybeSingle();

    if (!mounted) return;
    setState(() {
      _passengerNote = (rr?['passenger_note'] as String?);
    });
  }
}

Future<void> _loadPassengerNoteOnly() async {
  final rr = await _sb
      .from('ride_requests')
      .select('passenger_note')
      .eq('id', widget.rideId)
      .maybeSingle();

  if (!mounted) return;
  setState(() => _passengerNote = (rr?['passenger_note'] as String?));
  debugPrint('[RideStatus] note="${_passengerNote ?? 'NULL'}" for ${widget.rideId}');
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

  /// Load match id AND authoritative seats allocated for THIS booking
  Future<void> _loadMatchFacts() async {
    final row =
        await _sb
            .from('ride_matches')
            .select('id, seats_allocated')
            .eq('ride_request_id', widget.rideId)
            .maybeSingle();

    if (!mounted) return;

    final id = (row as Map?)?['id']?.toString();
    final seats = ((row?['seats_allocated'] as num?)?.toInt() ?? 1).clamp(1, 6);

    setState(() {
      _matchId = id;
      _seatsBilled = seats;
    });
  }

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
    } catch (_) {}
  }

  /// Riders vs seats across the route (active only)
  Future<void> _loadCarpoolSeatSnapshot() async {
    final routeId = _ride?['driver_route_id']?.toString();
    if (routeId == null) return;

    try {
      final rows = await _sb
          .from('ride_matches')
          .select('ride_request_id, seats_allocated, ride_requests(status)')
          .eq('driver_route_id', routeId);

      final activeStatuses = {'pending', 'accepted', 'en_route'};
      final active =
          (rows as List).map((e) => Map<String, dynamic>.from(e)).where((r) {
            final s =
                (r['ride_requests']?['status'] as String?)?.toLowerCase() ?? '';
            return activeStatuses.contains(s);
          }).toList();

      final bookings =
          active.map((r) => r['ride_request_id'].toString()).toSet().length;

      final seatsTotal = active.fold<int>(
        0,
        (acc, r) => acc + ((r['seats_allocated'] as num?)?.toInt() ?? 0),
      );

      if (!mounted) return;
      setState(() {
        _activeBookings = bookings == 0 ? 1 : bookings;
        _activeSeatsTotal = seatsTotal == 0 ? 1 : seatsTotal;
      });
    } catch (_) {
      // ignore; keep previous snapshot
    }
  }

  // ───────────────────────── Streams / Realtime ─────────────────────────

  void _watchParents() {
    _rideReqSub?.cancel();
    _rideReqSub = _sb
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', widget.rideId)
        .listen((_) async {
          await _loadRideComposite();
          await _loadPayment();
          await _loadMatchFacts();
          await _loadCarpoolSeatSnapshot();
          _syncPassengerPublisherToStatus();
          await _estimateFare();
          await _maybePromptRatingIfCompleted();
          await _loadPassengerNoteOnly();
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
          await _loadMatchFacts();
          await _loadCarpoolSeatSnapshot();
          _syncPassengerPublisherToStatus();
          await _estimateFare();
          await _maybePromptRatingIfCompleted();
          if (mounted) setState(() {});
        });
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

  // ───────────────────────── Live tracking ─────────────────────────

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
      if (!(_publisher!.isRunning)) _publisher!.start();
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

  // ───────────────────────── Fare estimation ─────────────────────────

  Future<void> _estimateFare() async {
    final p = _pickup;
    final d = _dropoff;
    if (p == null || d == null) return;

    final seats = _seatsBilled; // seats you actually booked
    final carpoolPassengers = _activeBookings; // unique bookings
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
      // keep last known _fareBx
    } finally {
      if (mounted) setState(() => _estimatingFare = false);
    }
  }

  // ───────────────────────── Helpers ─────────────────────────

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

  Widget _passengerNoteSection() {
  final note = (_passengerNote ?? '').trim();
  if (note.isEmpty) return const SizedBox.shrink();

  return _SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardTitle(
          icon: Icons.sticky_note_2_outlined,
          text: 'Your note to driver',
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border.all(color: Colors.amber.shade200),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(note),
        ),
      ],
    ),
  );
}

  String _peso(num? v) =>
      v == null ? '₱0.00' : '₱${(v.toDouble()).toStringAsFixed(2)}';

  Future<void> _cancelRide() async {
    try {
      await _sb.rpc('cancel_ride', params: {'p_ride_id': widget.rideId});
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

  // ───────────────────────── Safety ─────────────────────────

  void _openSos() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SosSheet(rideId: widget.rideId),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final fare = (_ride?['fare'] as num?)?.toDouble();
    final passengerId = _ride?['passenger_id']?.toString();
    final driverId = _ride?['driver_id']?.toString();
    final driverName = (_ride?['driver_name'] as String?) ?? '—';
    final bookingType = (_ride?['booking_type'] as String?) ?? 'shared';

    final center =
        _driverLive ?? _pickup ?? _dropoff ?? const LatLng(7.1907, 125.4553);

    final isCancelable = _status == 'pending' || _status == 'accepted';
    final isCanceled = _status == 'canceled';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withOpacity(0.4), Colors.transparent],
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
            backgroundColor: Colors.white.withOpacity(0.9),
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
        title: const Text(
          'Ride Status',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Quick SOS access from AppBar
          IconButton(
            tooltip: 'SOS',
            icon: const Icon(Icons.emergency_share),
            onPressed: _openSos,
          ),
          if (driverId != null) VerifiedBadge(userId: driverId, size: 22),
          if (driverId != null && _matchId != null)
  IconButton(
    tooltip: 'Chat with driver',
    icon: const Icon(Icons.message_outlined),
    onPressed: _isChatLocked
        ? () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Chat unavailable — this ride was cancelled, declined, or completed.',
                ),
              ),
            );
          }
        : () {
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
                  await _loadMatchFacts();
                  await _loadPlatformFeeRate();
                  await _loadCarpoolSeatSnapshot();
                  _syncPassengerPublisherToStatus();
                  await _estimateFare();
                  await _maybePromptRatingIfCompleted();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    if (isCanceled)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This ride has been canceled.',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isChatLocked)
  Container(
    padding: const EdgeInsets.all(10),
    margin: const EdgeInsets.only(top: 6),
    decoration: BoxDecoration(
      color: Colors.amber.shade50,
      border: Border.all(color: Colors.amber.shade200),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text(
      'Chat is disabled for this ride because it was cancelled, declined, or completed.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12),
    ),
  ),

                    if (isCanceled) const SizedBox(height: 12),

                    // Chips (status, pay, riders/seats)
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
                            icon: Icons.groups_2_outlined,
                            label: 'Riders: $_activeBookings',
                          ),
                          _Chip(
                            icon: Icons.event_seat_outlined,
                            label: 'Seats on route: $_activeSeatsTotal',
                          ),
                          _Chip(
                            icon: Icons.event_seat,
                            label:
                                _seatsBilled > 1
                                    ? 'Your seats: $_seatsBilled'
                                    : 'Your seats: 1',
                          ),
                          _Chip(
                            icon: Icons.group_outlined,
                            label: 'Booking: ${bookingType.toUpperCase()}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Map
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
                                            color: _purpleDark,
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
                                            color: _purple,
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
                                onPressed: () {
                                  if (_driverLive != null) {
                                    _map.move(_driverLive!, 16);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _MiniAction(
                                icon: Icons.place_outlined,
                                label: 'Pickup',
                                onPressed: () {
                                  if (_pickup != null) {
                                    _map.move(_pickup!, 16);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              _MiniAction(
                                icon: Icons.flag_outlined,
                                label: 'Dropoff',
                                onPressed: () {
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
                                style: TextButton.styleFrom(
                                  foregroundColor: _purple,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Driver summary
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

                    if ((_passengerNote ?? '').trim().isNotEmpty) ...[
  _passengerNoteSection(),
  const SizedBox(height: 12),
],

                    // Fare
                    if (_fareBx != null)
                      _SectionCard(
                        child: _FareBreakdownPro(
                          bx: _fareBx!,
                          peso: _peso,
                          estimating: _estimatingFare,
                          seatsBilledOverride: _seatsBilled,
                        ),
                      )
                    else if (fare != null)
                      _SectionCard(
                        child: _FareBreakdownSimple(
                          total: fare,
                          seats: _seatsBilled,
                          bookingType: bookingType,
                          peso: _peso,
                        ),
                      ),

                    if (_fareBx != null) ...[
                      const SizedBox(height: 12),
                      _SectionCard(
                        child: _CarpoolBreakdownTable(
                          currentCarpool: _activeBookings,
                          seatsRequested: _seatsBilled,
                          bx: _fareBx!,
                          fareService: _fareService,
                          peso: _peso,
                        ),
                      ),
                    ],

                    if (_status == 'completed' && driverId != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.star),
                        label: const Text('Rate your driver'),
                        onPressed: _maybePromptRatingIfCompleted,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      bottomNavigationBar: _buildBottomBar(
        passengerId ?? 'You',
        driverName,
        (_ride?['fare'] as num?)?.toDouble(),
        isCancelable: isCancelable,
      ),
    );
  }

  Widget _buildBottomBar(
    String passenger,
    String driverName,
    double? fare, {
    required bool isCancelable,
  }) {
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
                style: OutlinedButton.styleFrom(foregroundColor: _purple),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: Icon(
                  _status == 'en_route'
                      ? Icons.emergency_share
                      : isCancelable
                      ? Icons.cancel_outlined
                      : Icons.close,
                ),
                label: Text(
                  _status == 'en_route'
                      ? 'SOS'
                      : isCancelable
                      ? 'Cancel ride'
                      : 'Close',
                ),
                onPressed: () {
                  if (_status == 'en_route') {
                    _openSos(); // <-- Safety sheet
                  } else if (isCancelable) {
                    _cancelRide();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _status == 'en_route' ? Colors.red.shade700 : _purple,
                  foregroundColor: Colors.white,
                ),
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
              _detailRow(
  'Passenger note',
  ((_passengerNote ?? '').trim().isEmpty)
      ? '—'
      : _passengerNote!.trim(),
),
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
}

/* ───────────── Small UI helpers ───────────── */

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
  final VoidCallback onPressed;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        foregroundColor: _PassengerRideStatusPageState._purple,
        side: const BorderSide(color: _PassengerRideStatusPageState._purple),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _FareBreakdownSimple extends StatelessWidget {
  final double total;
  final int seats;
  final String bookingType;
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
  final int? seatsBilledOverride; // show allocated seats

  const _FareBreakdownPro({
    required this.bx,
    required this.peso,
    this.estimating = false,
    this.seatsBilledOverride,
  });

  @override
  Widget build(BuildContext context) {
    final seatsBilled = (seatsBilledOverride ?? bx.seatsBilled).clamp(1, 6);
    final perSeat = seatsBilled > 0 ? (bx.total / seatsBilled) : bx.total;

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
        row('Seats billed', '$seatsBilled'),
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
            _cell(peso(fb.total),  mono: false, bold: isCurrent),
_cell(peso(perSeat),   mono: false, bold: isCurrent),
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
          'How your fare changes with the number of riders sharing this route. Current riders highlighted.',
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
  const _TH(this.t);
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
