import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/features/payments/presentation/payment_method_sheet.dart';
import 'package:godavao/features/payments/presentation/gcash_proof_sheet.dart';
import 'package:godavao/main.dart' show localNotify;

class ConfirmRidePage extends StatefulWidget {
  final LatLng pickup;
  final LatLng destination;
  final String routeId;
  final String driverId;

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
  bool _loading = true;
  String? _error;

  Polyline? _routePolyline;
  double _distanceKm = 0;
  double _durationMin = 0;
  double _fare = 0;

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
    _loadRouteAndFare();
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
    setState(() {
      _loading = true;
      _error = null;
    });

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
        _routePolyline = d.toPolyline(color: Colors.blue, width: 4);
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
        _fare = total.roundToDouble();
        _loading = false;
      });
    } catch (_) {
      // Fallback straight line
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
          color: Colors.blue,
        );
        _distanceKm = double.parse(km.toStringAsFixed(2));
        _durationMin = double.parse(mins.toStringAsFixed(0));
        _fare = total.roundToDouble();
        _error = 'OSRM unavailable — using approximate route.';
        _loading = false;
      });
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

  /// RPC wrapper: create/hold a payment intent (escrow) for this ride.
  Future<String?> _createOrHoldPaymentIntent({
    required String rideId,
    required String method, // 'gcash' | 'cash'
    required double amount,
    required String driverUserId,
    String? proofUrl,
  }) async {
    final supabase = Supabase.instance.client;
    final res =
        await supabase
            .rpc(
              'api_create_or_hold_payment',
              params: {
                '_ride_id': rideId,
                '_method': method,
                '_amount': amount,
                '_payee_user_id': driverUserId,
                '_proof_url': proofUrl,
                '_hold_minutes': 120,
              },
            )
            .maybeSingle();
    return (res?['api_create_or_hold_payment'] as String?);
  }

  Future<void> _confirmRide() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not logged in')));
      }
      setState(() => _loading = false);
      return;
    }

    try {
      // 1) Create the ride first (so we have a ride_id for escrow)
      final req =
          await supabase
              .from('ride_requests')
              .insert({
                'passenger_id': user.id,
                'pickup_lat': widget.pickup.latitude,
                'pickup_lng': widget.pickup.longitude,
                'destination_lat': widget.destination.latitude,
                'destination_lng': widget.destination.longitude,
                'fare': _fare,
                'driver_route_id': widget.routeId,
                'status': 'pending',
                // Optional: audit fields
                // 'distance_km': _distanceKm,
                // 'duration_min': _durationMin,
              })
              .select('id')
              .maybeSingle();

      final rideReqId = (req)?['id'] as String?;
      if (rideReqId == null) {
        throw 'Failed to create ride request';
      }

      // 2) Ask for payment method
      final choice = await showModalBottomSheet<PaymentChoice>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const PaymentMethodSheet(),
      );

      if (choice == null) {
        // user dismissed — keep ride pending without a payment intent
        if (mounted) setState(() => _loading = false);
        return;
      }

      String? proofUrl;
      if (choice.method == 'gcash') {
        // 2a) Upload proof and get a storage URL
        proofUrl = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => GcashProofSheet(rideId: rideReqId, amount: _fare),
        );
        if (proofUrl == null) {
          // User backed out of upload; leave ride as-is
          if (mounted) setState(() => _loading = false);
          return;
        }
      }

      // 3) Create/hold the payment intent (escrow)
      final intentId = await _createOrHoldPaymentIntent(
        rideId: rideReqId,
        method: choice.method,
        amount: _fare,
        driverUserId: widget.driverId,
        proofUrl: proofUrl,
      );
      if (intentId == null) throw 'Payment initialization failed';

      // 4) Create the driver match after the payment intent exists
      await supabase.from('ride_matches').insert({
        'ride_request_id': rideReqId,
        'driver_route_id': widget.routeId,
        'driver_id': widget.driverId,
        'status': 'pending',
      });

      // 5) Persist chosen method on ride for UI convenience
      await supabase
          .from('ride_requests')
          .update({'payment_method': choice.method})
          .eq('id', rideReqId);

      // 6) Notify & navigate
      await _showNotification(
        'Ride Requested',
        choice.method == 'gcash'
            ? 'We received your GCash proof — payment is on hold.'
            : 'Cash selected — payment will be released after arrival.',
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/passenger_rides');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      await _showNotification('Request Failed', e.toString());
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (widget.pickup.latitude + widget.destination.latitude) / 2,
      (widget.pickup.longitude + widget.destination.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Your Ride')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: center, zoom: 13),
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
                        size: 40,
                      ),
                    ),
                    Marker(
                      point: widget.destination,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
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
                Text(
                  'Estimated Fare: ₱${_fare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _confirmRide,
                    child:
                        _loading
                            ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(
                              'Confirm & Pay ₱${_fare.toStringAsFixed(2)}',
                            ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
