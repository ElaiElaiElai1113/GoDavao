// lib/features/confirm/presentation/confirm_ride_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/core/fare_service.dart';
import 'package:godavao/features/payments/data/payment_service.dart';
import 'package:godavao/main.dart' show localNotify;

class ConfirmRidePage extends StatefulWidget {
  final LatLng pickup;
  final LatLng destination;
  final String routeId; // driver_routes.id
  final String driverId; // driver user id

  const ConfirmRidePage({
    required this.pickup,
    required this.destination,
    required this.routeId,
    required this.driverId,
    super.key,
  });

  @override
  State<ConfirmRidePage> createState() => _ConfirmRidePageState();
}

class _ConfirmRidePageState extends State<ConfirmRidePage> {
  // Theme / formatters
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  final _pesoFmt = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );
  String _peso(num? v) => _pesoFmt.format((v ?? 0).toDouble());

  // Services
  final _sb = Supabase.instance.client;
  final _fareService = FareService(
    rules: const FareRules(
      defaultPlatformFeeRate: 0.15,
      carpoolDiscountByPax: {2: 0.06, 3: 0.12, 4: 0.20, 5: 0.25},
    ),
  );

  // State
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  final _map = MapController();
  Polyline? _routePolyline;
  double _distanceKm = 0;
  double _durationMin = 0;

  int _seatsRequested = 1;
  int? _capacityTotal;
  int? _capacityAvailable;

  bool _pakyaw = false; // whole-vehicle booking
  int _carpoolSize = 1; // preview size (incl. me unless pakyaw)
  FareBreakdown? _fare;

  bool _didFit = false;
  bool _expandFare = true;
  Timer? _seatDebounce;

  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _seatDebounce?.cancel();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ───────────────── Bootstrap ─────────────────
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _didFit = false;
    });

    try {
      await Future.wait([_loadRouteGeometryAndMetrics(), _loadCapacity()]);
      await _refreshCarpoolAndFare();
    } catch (e) {
      _error ??= 'Something went wrong.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ────────────── Route / OSRM metrics ──────────────
  Future<void> _loadRouteGeometryAndMetrics() async {
    try {
      final d = await fetchOsrmRouteDetailed(
        start: widget.pickup,
        end: widget.destination,
        timeout: const Duration(seconds: 6),
      );
      final km = d.distanceMeters / 1000.0;
      final mins = max(d.durationSeconds / 60.0, 1.0);

      if (!mounted) return;
      setState(() {
        _routePolyline = d.toPolyline(
          color: _purpleDark.withOpacity(.9),
          width: 3,
        );
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
      });
    } catch (_) {
      // straight-line fallback
      final km = _haversineKm(widget.pickup, widget.destination);
      const avgKmh = 22.0;
      final mins = max((km / avgKmh) * 60.0, 1.0);

      if (!mounted) return;
      setState(() {
        _routePolyline = Polyline(
          points: [widget.pickup, widget.destination],
          color: _purpleDark.withOpacity(.9),
          strokeWidth: 3,
        );
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
        _error = 'OSRM unavailable — using approximate route.';
      });
    }

    // Fit map once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didFit) return;
      _didFit = true;
      final b = LatLngBounds.fromPoints([widget.pickup, widget.destination]);
      _map.fitCamera(
        CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(24)),
      );
    });
  }

  double _deg2rad(double d) => d * pi / 180.0;
  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  // ────────────── Capacity ──────────────
  Future<void> _loadCapacity() async {
    try {
      final route =
          await _sb
              .from('driver_routes')
              .select('capacity_total, capacity_available')
              .eq('id', widget.routeId)
              .single();

      final total = (route['capacity_total'] as num?)?.toInt();
      final avail = (route['capacity_available'] as num?)?.toInt();

      setState(() {
        _capacityTotal = total;
        _capacityAvailable = avail;
        if (_seatsRequested > (avail ?? 1)) {
          _seatsRequested = (avail ?? 1).clamp(1, 6);
        }
      });
    } catch (_) {
      _snack('Failed to load seats capacity.');
    }
  }

  int get _effectiveSeats =>
      _pakyaw ? (_capacityAvailable ?? 1).clamp(1, 6) : _seatsRequested;
  int get _maxSelectableSeats {
    final avail = _capacityAvailable ?? 6;
    return max(1, min(6, avail));
  }

  // ────────────── Carpool + Fare preview ──────────────
  Future<void> _refreshCarpoolAndFare() async {
    // Get current carpool size from server (excluding me)
    int paxExisting = 0;
    try {
      final res =
          await _sb
              .rpc(
                'carpool_size_for_route',
                params: {'p_route_id': widget.routeId},
              )
              .single();
      final v = (res as Map).values.first;
      paxExisting = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
    } catch (_) {
      paxExisting = 0;
    }

    // For preview, include me unless pakyaw (pakyaw disables discount)
    final paxForPricing = _pakyaw ? 1 : (paxExisting + 1);

    final fb = _fareService.estimateForDistance(
      distanceKm: _distanceKm,
      durationMin: _durationMin,
      seats: _effectiveSeats,
      carpoolPassengers: paxForPricing,
    );

    if (!mounted) return;
    setState(() {
      _carpoolSize = paxForPricing;
      _fare = fb;
    });
  }

  Future<void> _onChangeSeats(int v) async {
    if (v == _seatsRequested) return;
    setState(() => _seatsRequested = v);
    _seatDebounce?.cancel();
    _seatDebounce = Timer(
      const Duration(milliseconds: 250),
      _refreshCarpoolAndFare,
    );
  }

  // ────────────── Confirm Ride ──────────────
  Future<void> _confirmRide() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final user = _sb.auth.currentUser;
    if (user == null) {
      _snack('Not logged in');
      setState(() => _submitting = false);
      return;
    }

    final seatsToReserve = _effectiveSeats;
    final available = _capacityAvailable ?? 0;
    if (seatsToReserve > available) {
      _snack('Not enough seats available for your request.');
      setState(() => _submitting = false);
      return;
    }

    final fb = _fare;
    if (fb == null) {
      _snack('Fare not ready yet.');
      setState(() => _submitting = false);
      return;
    }

    final token = const Uuid().v4();
    final amount = fb.total;
    final fareBasis =
        (fb.subtotal + fb.nightSurcharge) * fb.surgeMultiplier * fb.seatsBilled;

    try {
      // 1) Create ride request with final fare & metadata
      final req =
          await _sb
              .from('ride_requests')
              .upsert({
                'client_token': token,
                'passenger_id': user.id,
                'pickup_lat': widget.pickup.latitude,
                'pickup_lng': widget.pickup.longitude,
                'destination_lat': widget.destination.latitude,
                'destination_lng': widget.destination.longitude,
                'fare': amount,
                'fare_basis': fareBasis,
                'carpool_discount_pct': fb.carpoolDiscountPct,
                'driver_route_id': widget.routeId,
                'status': 'pending',
                'requested_seats': seatsToReserve,
                'payment_method': 'gcash',
                'is_pakyaw': _pakyaw,
                'passenger_note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
              }, onConflict: 'client_token')
              .select('id')
              .single();

      final rideReqId = (req['id'] as String?) ?? '';
      if (rideReqId.isEmpty) throw 'Failed to create ride request';

      // 2) Allocate seats (atomic on DB)
      await _sb.rpc(
        'allocate_seats',
        params: {
          'p_driver_route_id': widget.routeId,
          'p_ride_request_id': rideReqId,
          'p_seats_requested': seatsToReserve,
        },
      );

      // 3) Payment hold
      final payments = PaymentsService(_sb);
      await payments.upsertOnHoldSafe(
        rideId: rideReqId,
        amount: amount,
        method: 'gcash',
        payerUserId: user.id,
        payeeUserId: widget.driverId,
      );

      // 4) Ensure a ride_match row exists
      await _ensureRideMatch(rideReqId);

      // 5) Ask server to reprice EVERYONE on this route now (keeps DB truthy)
      try {
        await _sb.rpc(
          'reprice_carpool_for_route',
          params: {'p_route_id': widget.routeId},
        );
      } catch (_) {
        // Non-fatal; UI already priced, backend will catch up
      }

      await _notify(
        'Ride Requested',
        _pakyaw
            ? 'Whole vehicle reserved & payment hold placed.'
            : 'Seats reserved & payment hold placed.',
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/passenger_rides');
    } on PostgrestException catch (e) {
      _snack(e.message);
      await _notify('Request Failed', e.message);
    } catch (e) {
      _snack('Error: $e');
      await _notify('Request Failed', e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _ensureRideMatch(String rideReqId) async {
    final payload = {
      'ride_request_id': rideReqId,
      'driver_route_id': widget.routeId,
      'driver_id': widget.driverId,
      'status': 'pending',
      'seats_allocated': _effectiveSeats,
    };

    try {
      await _sb.from('ride_matches').insert(payload);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing =
            await _sb
                .from('ride_matches')
                .select('id')
                .eq('ride_request_id', rideReqId)
                .inFilter('status', ['pending', 'accepted', 'en_route'])
                .limit(1)
                .maybeSingle();
        final id = (existing as Map?)?['id']?.toString();
        if (id != null) {
          await _sb
              .from('ride_matches')
              .update({
                'driver_route_id': widget.routeId,
                'driver_id': widget.driverId,
                'seats_allocated': _effectiveSeats,
              })
              .eq('id', id);
        } else {
          await _sb.from('ride_matches').insert(payload);
        }
      } else {
        rethrow;
      }
    }
  }

  // ────────────── Utils ──────────────
  Future<void> _notify(String title, String body) async {
    try {
      const android = AndroidNotificationDetails(
        'rides_channel',
        'Ride Updates',
        channelDescription: 'Alerts when you confirm a ride',
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
    } catch (_) {}
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ────────────── UI ──────────────

  @override
  Widget build(BuildContext context) {
    final fareTotal = _fare?.total ?? 0.0;
    final perSeat =
        (_effectiveSeats > 0) ? (fareTotal / _effectiveSeats) : fareTotal;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
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
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: const Text(
          'Confirm Ride',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),

      body: Column(
        children: [
          // --- MAP SECTION ---
          Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 230,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _buildMap(),
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.amber.shade900),
                ),
              ),
            ),

          // --- DETAILS SECTION ---
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadRouteGeometryAndMetrics();
                await _loadCapacity();
                await _refreshCarpoolAndFare();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                children: [
                  _InfoRow(
                    icon: Icons.route_outlined,
                    title: '${_distanceKm.toStringAsFixed(2)} km',
                    subtitle: '${_durationMin.toStringAsFixed(0)} min (est.)',
                  ),
                  const SizedBox(height: 10),
                  _buildCard(child: _pakyawCard()),
                  if (!_pakyaw) ...[
                    const SizedBox(height: 10),
                    _buildCard(child: _seatsCard()),
                  ],
                  if (_pakyaw) ...[
                    const SizedBox(height: 10),
                    _buildCard(child: _pakyawSeatsSummaryCard()),
                  ],
                  const SizedBox(height: 10),
                  _pickupDestinationBubbles(),

                  const SizedBox(height: 10),
                  _buildCard(child: _noteCard()),

                  const SizedBox(height: 10),
                  _buildCard(child: _fareCard(fareTotal, perSeat)),
                  if (!_pakyaw) ...[
                    const SizedBox(height: 10),
                    _buildCard(child: _carpoolPreviewTable()),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      // --- CONFIRM BUTTON ---
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withOpacity(0.9), _purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _purple.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, color: Colors.white),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                _loading || _submitting
                    ? 'Processing...'
                    : _pakyaw
                    ? 'Confirm Pakyaw • ${_peso(fareTotal)}'
                    : 'Confirm • ${_peso(fareTotal)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed:
                (_loading ||
                        _submitting ||
                        _fare == null ||
                        (_capacityAvailable ?? 0) <= 0)
                    ? null
                    : _confirmRide,
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMap() {
    final center = LatLng(
      (widget.pickup.latitude + widget.destination.latitude) / 2,
      (widget.pickup.longitude + widget.destination.longitude) / 2,
    );

    return AbsorbPointer(
      absorbing: true,
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 12,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.godavao.app',
          ),
          if (_routePolyline != null)
            PolylineLayer(polylines: [_routePolyline!]),
          MarkerLayer(
            markers: [
              _marker(widget.pickup, Icons.radio_button_checked, Colors.green),
              _marker(widget.destination, Icons.place, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Marker _marker(LatLng p, IconData icon, Color color) => Marker(
    point: p,
    width: 36,
    height: 36,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 20),
    ),
  );

  // ── Cards ─────────────────────────────────────────────
  Widget _pakyawCard() {
    final capAvail = _capacityAvailable ?? 0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.local_taxi_outlined,
            text: 'Pakyaw (Whole Vehicle)',
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reserve all available seats'),
            subtitle: Text(
              capAvail > 0
                  ? 'Will reserve $capAvail seat(s) on this route.'
                  : 'No seats available.',
            ),
            value: _pakyaw,
            onChanged:
                (capAvail <= 0 || _submitting)
                    ? null
                    : (v) async {
                      setState(() => _pakyaw = v);
                      await _refreshCarpoolAndFare();
                    },
          ),
          if (_pakyaw)
            Text(
              'No sharing. Carpool discounts disabled.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  Widget _pakyawSeatsSummaryCard() {
    final capAvail = _capacityAvailable ?? 0;
    final capTotal = _capacityTotal ?? 0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.event_seat, text: 'Seats'),
          const SizedBox(height: 6),
          Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Long text can take remaining width and wrap/ellipsis
            Expanded(
              child: Text(
                'Pakyaw: reserving all available seats',
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Compact right label scales down if tight
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Available: $capAvail / $capTotal',
                style: TextStyle(
                  fontSize: 13,
                  color: capAvail > 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
        ],
      ),
    );
  }

  Widget _seatsCard() {
    final capAvail = _capacityAvailable ?? 0;
    final capTotal = _capacityTotal ?? 0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.event_seat, text: 'Seats'),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Requested: $_seatsRequested',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Available: $capAvail / $capTotal',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      capAvail > 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SeatStepper(
            value: _seatsRequested,
            min: 1,
            max: _maxSelectableSeats,
            onChanged: _submitting ? (_) {} : _onChangeSeats,
          ),
          const SizedBox(height: 4),
          Text(
            'Tip: carpooling makes it cheaper per seat.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _noteCard() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _CardTitle(
        icon: Icons.sticky_note_2_outlined,
        text: 'Note to driver',
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _noteCtrl,
        maxLines: 3,
        maxLength: 500, // keep in sync with DB cap
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          hintText: 'Landmarks, gate code, special assistance, etc.',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    ],
  );
}

  Widget _pickupDestinationBubbles() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.my_location, text: 'Trip Summary'),
          const SizedBox(height: 10),
          Row(
            children: [
              _bubble(
                label: 'Pickup',
                color: Colors.green,
                active: true,
                icon: Icons.radio_button_checked,
              ),
              const Expanded(
                child: Divider(
                  thickness: 2,
                  color: Colors.grey,
                  indent: 10,
                  endIndent: 10,
                ),
              ),
              _bubble(
                label: 'Destination',
                color: Colors.red,
                active: true,
                icon: Icons.flag,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pickup comes first, followed by destination.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _bubble({
    required String label,
    required Color color,
    required bool active,
    required IconData icon,
  }) {
    return Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withOpacity(active ? 0.15 : 0.08),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  /// Fare with detailed breakdown (expandable)
  Widget _fareCard(double fareTotal, double perSeat) {
    final bx = _fare;

    return _Card(
      child: ExpansionTile(
        initiallyExpanded: _expandFare,
        onExpansionChanged: (v) => _expandFare = v,
        tilePadding: EdgeInsets.zero,
        title: const _CardTitle(icon: Icons.receipt_long, text: 'Fare'),
        childrenPadding: EdgeInsets.zero,
        children: [
          _fareRow('Total (₱)', _peso(fareTotal), strong: true),
          if (!_pakyaw) _fareRow('Per seat (₱)', _peso(perSeat)),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 6,
            spacing: 8,
            children: [
              if (_pakyaw)
                const _ChipIcon(
                  icon: Icons.local_taxi_outlined,
                  label: 'Pakyaw',
                ),
              _ChipIcon(
                icon: Icons.group_outlined,
                label: 'Carpool size: $_carpoolSize',
              ),
              _ChipIcon(
                icon: Icons.event_seat_outlined,
                label: 'Seats: ${_pakyaw ? _effectiveSeats : _seatsRequested}',
              ),
              _ChipIcon(
                icon: Icons.route_outlined,
                label: '${_distanceKm.toStringAsFixed(2)} km',
              ),
              _ChipIcon(
                icon: Icons.schedule_outlined,
                label: '${_durationMin.toStringAsFixed(0)} min',
              ),
              if ((bx?.nightSurcharge ?? 0) > 0)
                const _ChipIcon(
                  icon: Icons.nightlight_round,
                  label: 'Night surcharge',
                ),
              if ((bx?.surgeMultiplier ?? 1) > 1)
                _ChipIcon(
                  icon: Icons.trending_up,
                  label: 'Surge ${bx!.surgeMultiplier.toStringAsFixed(2)}×',
                ),
            ],
          ),
          if (bx != null) ...[
            const SizedBox(height: 10),
            Divider(height: 18, color: Colors.grey.shade200),
            _fareRow('Distance', '${bx.distanceKm.toStringAsFixed(2)} km'),
            _fareRow('Time', '${bx.durationMin.toStringAsFixed(0)} min'),
            const SizedBox(height: 6),
            _fareRow('Subtotal', _peso(bx.subtotal)),
            _fareRow('Night surcharge', _peso(bx.nightSurcharge)),
            _fareRow('Surge used', '${bx.surgeMultiplier.toStringAsFixed(2)}×'),
            const SizedBox(height: 6),
            _fareRow('Seats billed', '${bx.seatsBilled}'),
            _fareRow(
              'Carpool discount',
              '${(bx.carpoolDiscountPct * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 6),
            _fareRow('Platform fee', '- ${_peso(bx.platformFee)}'),
            _fareRow('Driver take (est.)', _peso(bx.driverTake)),
            Divider(height: 20, color: Colors.grey.shade200),
            _fareRow(
              'Per seat (approx.)',
              _peso(
                bx.seatsBilled > 0 ? (bx.total / bx.seatsBilled) : bx.total,
              ),
            ),
            _fareRow('Total', _peso(bx.total), strong: true),
          ],
        ],
      ),
    );
  }

  Widget _carpoolPreviewTable() {
    final cap = _capacityTotal ?? 4;
    final maxPax = cap.clamp(1, 5);
    final rows = <TableRow>[];

    for (int pax = 1; pax <= maxPax; pax++) {
      final fb = _fareService.estimateForDistance(
        distanceKm: _distanceKm,
        durationMin: _durationMin,
        seats: _seatsRequested,
        carpoolPassengers: pax,
      );
      final perSeat =
          _seatsRequested > 0 ? (fb.total / _seatsRequested) : fb.total;
      rows.add(_tableRow(['$pax', _peso(fb.total), _peso(perSeat)]));
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.ssid_chart_outlined,
            text: 'Carpool savings preview',
          ),
          const SizedBox(height: 6),
          Text(
            'See how price changes as more riders share the trip.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              _tableHeader(['Riders', 'Total (₱)', 'Per seat (₱)']),
              ...rows,
            ],
          ),
        ],
      ),
    );
  }

  // Table / row helpers
  TableRow _tableHeader(List<String> cols) => TableRow(
    decoration: BoxDecoration(color: Colors.grey.shade100),
    children:
        cols
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(
                  c,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            )
            .toList(),
  );

  TableRow _tableRow(List<String> cols) => TableRow(
    children:
        cols
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(c, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(),
  );

  Widget _fareRow(String label, String value, {bool strong = false}) => Padding(
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
            fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/* ───────────── Small UI helpers ───────────── */

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
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

class _ChipIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipIcon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _InfoRow({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF6A27F7).withOpacity(0.1),
            child: Icon(icon, color: const Color(0xFF6A27F7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _SeatStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canDec = value > min;
    final canInc = value < max;
    return Row(
      children: [
        _RoundIconBtn(
          icon: Icons.remove,
          onTap: canDec ? () => onChanged(value - 1) : null,
        ),
        const SizedBox(width: 12),
        Text(
          '$value',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        _RoundIconBtn(
          icon: Icons.add,
          onTap: canInc ? () => onChanged(value + 1) : null,
        ),
        const Spacer(),
        Text(
          'Max: $max',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundIconBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade200 : const Color(0xFF6A27F7),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: onTap == null ? Colors.grey.shade500 : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
