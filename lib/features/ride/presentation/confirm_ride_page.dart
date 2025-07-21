import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfirmRidePage extends StatefulWidget {
  final LatLng pickup;
  final LatLng destination;

  const ConfirmRidePage({
    required this.pickup,
    required this.destination,
    Key? key,
  }) : super(key: key);

  @override
  State<ConfirmRidePage> createState() => _ConfirmRidePageState();
}

class _ConfirmRidePageState extends State<ConfirmRidePage> {
  bool _loading = true;
  double _distanceKm = 0.0;
  double _fare = 0.0;

  final Distance _distance = const Distance();

  @override
  void initState() {
    super.initState();
    _calculateFare();
  }

  void _calculateFare() {
    // straight‑line distance (in meters)
    final meters = _distance(widget.pickup, widget.destination);
    final km = meters / 1000;

    // Dynamic pricing (WIP)
    const baseFare = 50.0;
    const perKmRate = 10.0;
    const perMinuteRate = 2.0;
    // assume avg speed 40 km/h → minutes = (km/40)*60
    final mins = (km / 40) * 60;

    final fare = baseFare + (perKmRate * km) + (perMinuteRate * mins);

    setState(() {
      _distanceKm = km;
      _fare = fare;
      _loading = false;
    });
  }

  Future<void> _confirmRide() async {
    setState(() => _loading = true);

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in')));
      setState(() => _loading = false);
      return;
    }

    try {
      // Insert ride request with fare
      await supabase.from('ride_requests').insert({
        'passenger_id': user.id,
        'pickup_lat': widget.pickup.latitude,
        'pickup_lng': widget.pickup.longitude,
        'destination_lat': widget.destination.latitude,
        'destination_lng': widget.destination.longitude,
        'fare': _fare,
      });

      Navigator.pushReplacementNamed(context, '/passenger_rides');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating ride: $e')));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Your Ride')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: widget.pickup, zoom: 13),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.yourcompany.godavao',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [widget.pickup, widget.destination],
                      strokeWidth: 4,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.green,
                      ),
                    ),
                    Marker(
                      point: widget.destination,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Fare details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Distance: ${_distanceKm.toStringAsFixed(2)} km'),
                const SizedBox(height: 8),
                Text('Estimated Fare: ₱${_fare.toStringAsFixed(2)}'),
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
                                color: Colors.white,
                                strokeWidth: 2,
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
