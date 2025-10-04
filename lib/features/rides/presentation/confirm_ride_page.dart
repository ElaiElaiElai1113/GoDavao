import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  final _fareService = FareService(
    rules: const FareRules(
      defaultPlatformFeeRate: 0.15,
      carpoolDiscountByPax: {2: 0.06, 3: 0.12, 4: 0.20, 5: 0.25},
    ),
  );

  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Polyline? _routePolyline;
  double _distanceKm = 0;
  double _durationMin = 0;

  // Seating
  int _seatsRequested = 1;
  int? _capacityTotal;
  int? _capacityAvailable;

  // Pakyaw
  bool _pakyaw = false;

  // Carpool size (unique riders on this route incl. current user)
  int _carpoolSize = 1;

  FareBreakdown? _fare;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
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

  /* ---------- OSRM + Metrics ---------- */

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
          color: _purpleDark.withOpacity(0.8),
          width: 3,
        );
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
      });
    } catch (_) {
      // fallback line
      final km = _haversineKm(widget.pickup, widget.destination);
      const avgKmh = 22.0;
      final mins = max((km / avgKmh) * 60.0, 1.0);

      if (!mounted) return;
      setState(() {
        _routePolyline = Polyline(
          points: [widget.pickup, widget.destination],
          strokeWidth: 3,
          color: _purpleDark.withOpacity(0.8),
        );
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
        _error = 'OSRM unavailable — using approximate route.';
      });
    }
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

  /* ---------- Capacity ---------- */

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
        final a = _capacityAvailable ?? 1;
        if (_seatsRequested > a) {
          _seatsRequested = a.clamp(1, 6);
        }
      });
    } catch (e) {
      _snack('Failed to load seats capacity.');
    }
  }

  /* ---------- Helpers for pakyaw ---------- */

  int get _effectiveSeats {
    if (_pakyaw) return (_capacityAvailable ?? 1).clamp(1, 6);
    return _seatsRequested;
  }

  /* ---------- Carpool + Fare ---------- */

  Future<void> _refreshCarpoolAndFare() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    final pax =
        _pakyaw
            ? 1 // whole vehicle = one party, no carpool discount
            : await _fetchCarpoolSize(
              sb: _sb,
              driverRouteId: widget.routeId,
              currentPassengerId: user.id,
            );

    final fb = _fareService.estimateForDistance(
      distanceKm: _distanceKm,
      durationMin: _durationMin,
      seats: _effectiveSeats,
      carpoolPassengers: pax,
    );

    if (!mounted) return;
    setState(() {
      _carpoolSize = pax;
      _fare = fb;
    });
  }

  Future<int> _fetchCarpoolSize({
    required SupabaseClient sb,
    required String driverRouteId,
    required String currentPassengerId,
  }) async {
    final rows = await sb
        .from('ride_requests')
        .select('passenger_id')
        .eq('driver_route_id', driverRouteId)
        .inFilter('status', ['pending', 'accepted', 'en_route']);

    final set = <String>{};
    for (final r in (rows as List)) {
      final pid = r['passenger_id'] as String?;
      if (pid != null && pid.isNotEmpty) set.add(pid);
    }
    set.add(currentPassengerId);
    return set.length;
  }

  /* ---------- Confirm Ride ---------- */

  Future<void> _confirmRide() async {
    setState(() => _loading = true);
    final user = _sb.auth.currentUser;
    final token = const Uuid().v4();

    if (user == null) {
      _snack('Not logged in');
      setState(() => _loading = false);
      return;
    }

    final seatsToReserve = _effectiveSeats;
    final available = _capacityAvailable ?? 0;
    if (seatsToReserve > available) {
      _snack('Not enough seats available for your request.');
      setState(() => _loading = false);
      return;
    }

    final amount = _fare?.total ?? 0;

    try {
      // 1) ride_requests
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
                'driver_route_id': widget.routeId,
                'status': 'pending',
                'requested_seats': seatsToReserve,
                'payment_method': 'gcash',
                'is_pakyaw': _pakyaw,
              }, onConflict: 'client_token')
              .select('id')
              .single();

      final rideReqId = (req['id'] as String?) ?? '';
      if (rideReqId.isEmpty) throw 'Failed to create ride request';

      // 2) allocate seats atomically
      await _sb.rpc(
        'allocate_seats',
        params: {
          'p_driver_route_id': widget.routeId,
          'p_ride_request_id': rideReqId,
          'p_seats_requested': seatsToReserve,
        },
      );

      // 3) payment hold
      final payments = PaymentsService(_sb);
      await payments.upsertOnHoldSafe(
        rideId: rideReqId,
        amount: amount,
        method: 'gcash',
        payerUserId: user.id,
        payeeUserId: widget.driverId,
      );

      // 4) mark payment method (best-effort)
      try {
        await _sb
            .from('ride_requests')
            .update({'payment_method': 'gcash'})
            .eq('id', rideReqId);
      } catch (_) {}

      // 5) ensure a ride_match row exists
      await _ensureRideMatch(rideReqId);

      await _showNotification(
        'Ride Requested',
        _pakyaw
            ? 'Whole vehicle reserved & payment hold placed.'
            : 'Seats reserved & payment hold placed.',
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/passenger_rides');
    } on PostgrestException catch (e) {
      _snack(e.message);
      await _showNotification('Request Failed', e.message);
    } catch (e) {
      _snack('Error: $e');
      await _showNotification('Request Failed', e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
      return;
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
        return;
      }
      rethrow;
    }
  }

  /* ---------- Utils ---------- */

  Future<void> _showNotification(String title, String body) async {
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
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  int get _maxSelectableSeats {
    final avail = _capacityAvailable ?? 6;
    return max(1, min(6, avail));
  }

  List<_FarePreview> _buildCarpoolPreview() {
    final cap = _capacityTotal ?? 4;
    final maxPax = cap.clamp(1, 5);
    final list = <_FarePreview>[];
    for (int pax = 1; pax <= maxPax; pax++) {
      final fb = _fareService.estimateForDistance(
        distanceKm: _distanceKm,
        durationMin: _durationMin,
        seats: _seatsRequested,
        carpoolPassengers: pax,
      );
      final perSeat =
          _seatsRequested > 0 ? (fb.total / _seatsRequested) : fb.total;
      list.add(_FarePreview(pax: pax, total: fb.total, perSeat: perSeat));
    }
    return list;
  }

  Future<void> _onChangeSeats(int v) async {
    if (v == _seatsRequested) return;
    setState(() => _seatsRequested = v);
    await _refreshCarpoolAndFare();
  }

  /* ---------- UI ---------- */

  @override
  Widget build(BuildContext context) {
    final mapHeight = 240.0;
    final fareTotal = _fare?.total ?? 0.0;
    final seatsDenom = _effectiveSeats > 0 ? _effectiveSeats : 1;
    final perSeat = fareTotal / seatsDenom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Ride'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          SizedBox(height: mapHeight, child: _buildMap()),

          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.amber.shade900),
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadRouteGeometryAndMetrics();
                await _loadCapacity();
                await _refreshCarpoolAndFare();
              },
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _InfoRow(
                    icon: Icons.route_outlined,
                    title: '${_distanceKm.toStringAsFixed(2)} km',
                    subtitle: '${_durationMin.toStringAsFixed(0)} min (est.)',
                  ),
                  const SizedBox(height: 8),

                  // Pakyaw toggle card
                  _pakyawCard(),
                  const SizedBox(height: 8),

                  // Seats card: hide selector when pakyaw (show summary instead)
                  if (!_pakyaw) _seatsCard(),
                  if (_pakyaw) _pakyawSeatsSummaryCard(),
                  const SizedBox(height: 8),

                  // Fare with detailed breakdown
                  _fareCard(fareTotal, perSeat),
                  const SizedBox(height: 8),

                  if (!_pakyaw) _carpoolCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label:
                  _loading
                      ? const Text('Processing...')
                      : Text(
                        _pakyaw
                            ? 'Confirm Pakyaw • ₱${fareTotal.toStringAsFixed(2)}'
                            : 'Confirm • ₱${fareTotal.toStringAsFixed(2)}',
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed:
                  (_loading || _fare == null || (_capacityAvailable ?? 0) <= 0)
                      ? null
                      : _confirmRide,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final bounds = LatLngBounds.fromPoints([widget.pickup, widget.destination]);
    final center = LatLng(
      (widget.pickup.latitude + widget.destination.latitude) / 2,
      (widget.pickup.longitude + widget.destination.longitude) / 2,
    );

    return AbsorbPointer(
      absorbing: true,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 12,
          bounds: bounds,
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

  /* ---------- Cards ---------- */

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
                (capAvail <= 0)
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pakyaw: reserving all available seats',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
            onChanged: (v) => _onChangeSeats(v),
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

  /// UPDATED: shows a rich fare breakdown using `FareBreakdown`
  Widget _fareCard(double fareTotal, double perSeat) {
    final bx = _fare;

    String peso(num? v) => v == null ? '₱0.00' : '₱${v.toStringAsFixed(2)}';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.receipt_long, text: 'Fare'),
          const SizedBox(height: 6),

          // Totals (always shown)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total (₱)', style: TextStyle(color: Colors.grey.shade700)),
              Text(
                peso(fareTotal),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!_pakyaw)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Per seat (₱)',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                Text(
                  peso(perSeat),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),

          const SizedBox(height: 10),

          // Quick chips
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
            ],
          ),

          // Detailed breakdown (only if we have it)
          if (bx != null) ...[
            const SizedBox(height: 12),
            Divider(height: 18, color: Colors.grey.shade200),

            _fareRow('Distance', '${bx.distanceKm.toStringAsFixed(2)} km'),
            _fareRow('Time', '${bx.durationMin.toStringAsFixed(0)} min'),
            const SizedBox(height: 6),

            _fareRow('Subtotal', peso(bx.subtotal)),
            _fareRow('Night surcharge', peso(bx.nightSurcharge)),
            _fareRow('Surge used', '${bx.surgeMultiplier.toStringAsFixed(2)}×'),
            const SizedBox(height: 6),

            _fareRow('Seats billed', '${bx.seatsBilled}'),
            _fareRow(
              'Carpool discount',
              '${(bx.carpoolDiscountPct * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 6),

            _fareRow('Platform fee', '- ${peso(bx.platformFee)}'),
            _fareRow('Driver take (est.)', peso(bx.driverTake)),

            Divider(height: 20, color: Colors.grey.shade200),
            _fareRow(
              'Per seat (approx.)',
              peso(bx.seatsBilled > 0 ? (bx.total / bx.seatsBilled) : bx.total),
            ),
            _fareRow('Total', peso(bx.total), strong: true),
          ],
        ],
      ),
    );
  }

  Widget _carpoolCard() {
    final rows = _buildCarpoolPreview();
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
              ...rows.map(
                (r) => _tableRow([
                  '${r.pax}',
                  '₱${r.total.toStringAsFixed(2)}',
                  '₱${r.perSeat.toStringAsFixed(2)}',
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  /// Small row helper for the fare breakdown
  Widget _fareRow(String label, String value, {bool strong = false}) {
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
              fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/* ===== Small UI helpers ===== */

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
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
        Icon(icon, color: Color(0xFF6A27F7)),
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
      radius: 22,
      child: Container(
        width: 38,
        height: 38,
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

class _FarePreview {
  final int pax;
  final double total;
  final double perSeat;
  _FarePreview({required this.pax, required this.total, required this.perSeat});
}
