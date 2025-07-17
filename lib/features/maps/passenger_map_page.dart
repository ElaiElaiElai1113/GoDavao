import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:godavao/features/ride_matching/data/ride_matching_service.dart';
import 'package:godavao/features/ride_requests/data/ride_request_service.dart';
import 'package:godavao/features/ride_requests/models/ride_request_model.dart';
import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PassengerMapPage extends StatefulWidget {
  const PassengerMapPage({super.key});

  @override
  State<PassengerMapPage> createState() => _PassengerMapPageState();
}

class _PassengerMapPageState extends State<PassengerMapPage> {
  final LatLng _davaoCenter = LatLng(7.1907, 125.4553);
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;

  String? _pickupAddress;
  String? _destinationAddress;

  void _onMapTap(TapPosition tapPosition, LatLng latlng) async {
    final address = await _getAddressFromLatLng(latlng);
    setState(() {
      if (_pickupLocation == null) {
        _pickupLocation = latlng;
        _pickupAddress = address;
      } else if (_destinationLocation == null) {
        _destinationLocation = latlng;
        _destinationAddress = address;
      } else {
        _pickupLocation = latlng;
        _pickupAddress = address;
        _destinationLocation = null;
        _destinationAddress = null;
      }
    });
  }

  Future<String> _getAddressFromLatLng(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      final place = placemarks.first;
      return '${place.street}, ${place.locality}, ${place.administrativeArea}';
    } catch (e) {
      return 'Unknown location';
    }
  }

  void _confirmRideRequest() async {
    if (_pickupLocation != null && _destinationLocation != null) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final ride = RideRequest(
        passengerId: user.id,
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        destinationLat: _destinationLocation!.latitude,
        destinationLng: _destinationLocation!.longitude,
      );

      try {
        // 1. Save ride request
        final rideId = await RideRequestService().saveRideRequest(ride);

        // 2. Attempt match
        await RideMatchService().matchRideRequest(
          rideRequestId: rideId,
          pickup: _pickupLocation!,
          destination: _destinationLocation!,
        );

        // 3. Fetch matched driver
        final match =
            await Supabase.instance.client
                .from('ride_matches')
                .select('id, driver_routes(driver_id, users(name))')
                .eq('ride_request_id', rideId)
                .limit(1)
                .maybeSingle();

        if (!mounted) return;

        if (match != null && match['id'] != null) {
          final matchId = match['id'] as String;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PassengerRideStatusPage(matchId: matchId),
            ),
          );
        } else {
          showDialog(
            context: context,
            builder:
                (_) => AlertDialog(
                  title: const Text('Ride Confirmed'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Pickup Address: $_pickupAddress"),
                      Text("Destination Address: $_destinationAddress"),
                      const SizedBox(height: 10),
                      Text("Ride saved, but no match found yet."),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Pickup and Destination')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              center: _davaoCenter,
              zoom: 13.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.godavao',
              ),
              if (_pickupLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pickupLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                    if (_destinationLocation != null)
                      Marker(
                        point: _destinationLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                  ],
                ),
              if (_pickupLocation != null && _destinationLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_pickupLocation!, _destinationLocation!],
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
            ],
          ),
          if (_pickupLocation != null && _destinationLocation != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _confirmRideRequest,
                child: const Text("Confirm Ride Request"),
              ),
            ),
        ],
      ),
    );
  }
}
