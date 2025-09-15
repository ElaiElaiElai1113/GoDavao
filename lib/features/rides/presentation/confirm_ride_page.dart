import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/features/payments/data/payment_service.dart';
import 'package:godavao/features/payments/presentation/payment_status_chip.dart';
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
  // UI theme (align with GoDavao)
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  bool _loading = true;
  String? _error;

  Polyline? _routePolyline;
  double _distanceKm = 0;
  double _durationMin = 0;
  double _fare = 0;

  // Seating
  int _seatsRequested = 1;
  int? _capacityTotal;
  int? _capacityAvailable;

  // Fare rules
  static const double _baseFare = 50.0;
  static const double _perKm = 10.0;
  static const double _perMin = 2.0;
  static const double _minFare = 70.0;
  static const double _bookingFee = 5.0;
  static const double _nightPct = 0.15;
  static const int _nightStartHour = 23;
  static const int _nightEndHour = 5;

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
    await Future.wait([_loadRouteAndFare(), _loadCapacity()]);
    if (mounted) setState(() => _loading = false);
  }

  bool _isNight(DateTime now) {
    final h = now.hour;
    return (h >= _nightStartHour) || (h <= _nightEndHour);
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

  Future<void> _loadRouteAndFare() async {
    try {
      final d = await fetchOsrmRouteDetailed(
        start: widget.pickup,
        end: widget.destination,
        timeout: const Duration(seconds: 6),
      );

      final km = d.distanceMeters / 1000.0;
      final mins = max(d.durationSeconds / 60.0, 1.0);
      double subtotal =
          _baseFare + (_perKm * km) + (_perMin * mins) + _bookingFee;
      subtotal = max(subtotal, _minFare);
      final night = _isNight(DateTime.now()) ? subtotal * _nightPct : 0.0;
      final total = subtotal + night;

      if (!mounted) return;
      setState(() {
        _routePolyline = d.toPolyline(color: Color(0xFF6A27F7), width: 4);
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
        _fare = total.roundToDouble();
      });
    } catch (_) {
      // Fallback if OSRM is unavailable
      final km = _haversineKm(widget.pickup, widget.destination);
      const avgKmh = 22.0;
      final mins = max((km / avgKmh) * 60.0, 1.0);
      double subtotal =
          _baseFare + (_perKm * km) + (_perMin * mins) + _bookingFee;
      subtotal = max(subtotal, _minFare);
      final night = _isNight(DateTime.now()) ? subtotal * _nightPct : 0.0;
      final total = subtotal + night;

      if (!mounted) return;
      setState(() {
        _routePolyline = Polyline(
          points: [widget.pickup, widget.destination],
          strokeWidth: 4,
          color: Color(0xFF6A27F7),
        );
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
        _fare = total.roundToDouble();
        _error = 'OSRM unavailable — using approximate route.';
      });
    }
  }

  Future<void> _loadCapacity() async {
    try {
      final sb = Supabase.instance.client;
      final route =
          await sb
              .from('driver_routes')
              .select('capacity_total, capacity_available')
              .eq('id', widget.routeId)
              .single();

      setState(() {
        _capacityTotal = (route['capacity_total'] as num?)?.toInt();
        _capacityAvailable = (route['capacity_available'] as num?)?.toInt();
        // clamp requested seats if > available
        if (_capacityAvailable != null &&
            _seatsRequested > _capacityAvailable!) {
          _seatsRequested = max(1, _capacityAvailable!);
        }
      });
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Failed to load seats capacity.');
    }
  }

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

  Future<void> _confirmRide() async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    final token = const Uuid().v4();

    if (user == null) {
      _snack('Not logged in');
      setState(() => _loading = false);
      return;
    }

    // Client-side pre-check (server RPC will re-check)
    final available = _capacityAvailable ?? 0;
    if (_seatsRequested > available) {
      _snack('Not enough seats available for your request.');
      setState(() => _loading = false);
      return;
    }

    try {
      // 1) Upsert ride_requests (idempotent via client_token)
      final req =
          await sb
              .from('ride_requests')
              .upsert({
                'client_token': token,
                'passenger_id': user.id,
                'pickup_lat': widget.pickup.latitude,
                'pickup_lng': widget.pickup.longitude,
                'destination_lat': widget.destination.latitude,
                'destination_lng': widget.destination.longitude,
                'fare': _fare,
                'driver_route_id': widget.routeId,
                'status': 'pending',
                'requested_seats': _seatsRequested,
              }, onConflict: 'client_token')
              .select('id')
              .single();

      final rideReqId = req['id'] as String;
      if (rideReqId.isEmpty) {
        throw 'Failed to create ride request';
      }

      // 2) **Atomic seat allocation** via RPC
      await sb.rpc(
        'allocate_seats',
        params: {
          'p_driver_route_id': widget.routeId,
          'p_ride_request_id': rideReqId,
          'p_seats_requested': _seatsRequested,
        },
      );

      // 3) Payment hold (GCash sim)
      final payments = PaymentsService(sb);
      await payments.upsertOnHoldSafe(
        rideId: rideReqId,
        amount: _fare,
        method: 'gcash',
        payerUserId: user.id,
        payeeUserId: widget.driverId,
      );

      // 4) Optional: mark payment_method
      try {
        await sb
            .from('ride_requests')
            .update({'payment_method': 'gcash'})
            .eq('id', rideReqId);
      } catch (_) {}

      await _showNotification(
        'Ride Requested',
        'Seats reserved & payment on hold.',
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

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (widget.pickup.latitude + widget.destination.latitude) / 2,
      (widget.pickup.longitude + widget.destination.longitude) / 2,
    );

    final capAvail = _capacityAvailable ?? 0;
    final capTotal = _capacityTotal ?? 0;
    final notEnough = _seatsRequested > capAvail;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Confirm Your Ride')),
      body: Stack(
        children: [
          // Map background with route
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 15),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (_routePolyline != null)
                  PolylineLayer(polylines: [_routePolyline!]),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.green,
                        size: 30,
                      ),
                    ),
                    Marker(
                      point: widget.destination,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.pin_drop,
                        color: Colors.red,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom summary card
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
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                      ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Distance: ${_distanceKm.toStringAsFixed(2)} km'),
                        Text('Time: ${_durationMin.toStringAsFixed(0)} min'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Estimated Fare: ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '₱${_fare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _purple,
                          ),
                        ),
                        const Spacer(),
                        PaymentStatusChip(status: 'on_hold'),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Seats stepper + capacity chip
                    Row(
                      children: [
                        const Text('Passengers'),
                        const SizedBox(width: 12),
                        _Stepper(
                          value: _seatsRequested,
                          min: 1,
                          max: _maxSelectableSeats,
                          onChanged:
                              _loading
                                  ? null
                                  : (v) => setState(() => _seatsRequested = v),
                        ),
                        const Spacer(),
                        Chip(label: Text('Seats: $capAvail / $capTotal')),
                      ],
                    ),
                    if (notEnough)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: const Text(
                            'Not enough seats available',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // Big purple CTA (gradient)
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
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed:
                              (_loading || notEnough) ? null : _confirmRide,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child:
                              _loading
                                  ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Text(
                                    'Confirm & Hold ₱${_fare.toStringAsFixed(2)} (GCash)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
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

/// Small reusable stepper control (— 1 2 3 +)
class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canDec = value > min;
    final canInc = value < max;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed:
              (onChanged == null || !canDec)
                  ? null
                  : () => onChanged!(value - 1),
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed:
              (onChanged == null || !canInc)
                  ? null
                  : () => onChanged!(value + 1),
        ),
      ],
    );
  }
}
