import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String rideRequestId;
  const PassengerRideStatusPage({super.key, required this.rideRequestId});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  final supabase = Supabase.instance.client;

  String status = 'pending';
  String pickupAddress = '';
  String destinationAddress = '';
  String? driverName;
  bool loading = true;

  late final StreamSubscription<List<Map<String, dynamic>>> _rideSub;

  final statusStages = ['pending', 'accepted', 'en_route', 'completed'];

  @override
  void initState() {
    super.initState();
    _initRide();
    _subscribeToRideStatus();
  }

  Future<void> _initRide() async {
    final result =
        await supabase
            .from('ride_requests')
            .select('pickup_lat, pickup_lng, destination_lat, destination_lng')
            .eq('id', widget.rideRequestId)
            .maybeSingle();

    if (result == null) return;

    final pickup = await _reverseGeocode(
      result['pickup_lat'],
      result['pickup_lng'],
    );
    final destination = await _reverseGeocode(
      result['destination_lat'],
      result['destination_lng'],
    );

    if (!mounted) return;
    setState(() {
      pickupAddress = pickup;
      destinationAddress = destination;
    });

    _fetchDriverName();
  }

  Future<void> _fetchDriverName() async {
    final match =
        await supabase
            .from('ride_matches')
            .select('driver_routes(driver_id, users(name))')
            .eq('ride_request_id', widget.rideRequestId)
            .maybeSingle();

    if (match != null &&
        match['driver_routes'] != null &&
        match['driver_routes']['users'] != null) {
      if (!mounted) return;
      setState(() {
        driverName = match['driver_routes']['users']['name'] ?? 'Driver';
      });
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  void _subscribeToRideStatus() {
    _rideSub = supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', widget.rideRequestId)
        .listen((event) {
          if (!mounted || event.isEmpty) return;
          setState(() {
            status = event.first['status'] ?? 'pending';
          });
        });
  }

  Future<String> _reverseGeocode(dynamic lat, dynamic lng) async {
    try {
      final latD = lat is double ? lat : double.tryParse(lat.toString());
      final lngD = lng is double ? lng : double.tryParse(lng.toString());
      if (latD == null || lngD == null) return 'Unknown location';

      final placemarks = await placemarkFromCoordinates(latD, lngD);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return "${place.street}, ${place.locality}, ${place.country}";
      }
    } catch (e) {
      debugPrint("Geocoding failed: $e");
    }
    return 'Unknown location';
  }

  Future<void> _cancelRide() async {
    await supabase
        .from('ride_requests')
        .update({'status': 'cancelled'})
        .eq('id', widget.rideRequestId);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ride cancelled')));
    Navigator.pop(context);
  }

  int getCurrentStep() {
    final index = statusStages.indexOf(status);
    return index >= 0 ? index : 0;
  }

  @override
  void dispose() {
    _rideSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ride Status")),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (driverName != null)
                      Text(
                        "Driver: $driverName",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    const SizedBox(height: 12),
                    Text("Pickup: $pickupAddress"),
                    Text("Destination: $destinationAddress"),
                    const SizedBox(height: 24),
                    Stepper(
                      currentStep: getCurrentStep(),
                      steps:
                          statusStages
                              .map(
                                (s) => Step(
                                  title: Text(s.toUpperCase()),
                                  content: const SizedBox.shrink(),
                                  isActive:
                                      statusStages.indexOf(s) <=
                                      getCurrentStep(),
                                ),
                              )
                              .toList(),
                    ),
                    const Spacer(),
                    if (status == 'pending')
                      Center(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.cancel),
                          onPressed: _cancelRide,
                          label: const Text("Cancel Ride"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );
  }
}
