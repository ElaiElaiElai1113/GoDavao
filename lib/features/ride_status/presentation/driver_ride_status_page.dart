import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String matchId;
  const DriverRideStatusPage({super.key, required this.matchId});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? ride;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRide();
  }

  Future<void> _loadRide() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final response =
          await supabase
              .from('ride_matches')
              .select('''
            id,
            status,
            ride_requests(
              pickup_lat,
              pickup_lng,
              destination_lat,
              destination_lng,
              users(name)
            )
          ''')
              .eq('id', widget.matchId)
              .maybeSingle();

      if (response == null) {
        throw Exception('Ride not found');
      }

      setState(() {
        ride = response;
        loading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading ride details: $e';
        loading = false;
      });
    }
  }

  Future<String> _reverseGeocode(dynamic lat, dynamic lng) async {
    try {
      final latDouble = double.tryParse(lat.toString());
      final lngDouble = double.tryParse(lng.toString());

      if (latDouble == null || lngDouble == null) return 'Unknown location';

      final placemarks = await placemarkFromCoordinates(latDouble, lngDouble);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return '${place.street}, ${place.locality}, ${place.country}';
      }
    } catch (e) {
      debugPrint("Reverse geocoding failed: $e");
    }
    return 'Unknown location';
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await supabase
          .from('ride_matches')
          .update({'status': newStatus})
          .eq('id', widget.matchId);

      _loadRide();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
    }
  }

  Widget _buildStatusControls(String currentStatus) {
    if (currentStatus == 'pending') {
      return ElevatedButton(
        onPressed: () => _updateStatus('accepted'),
        child: const Text('Accept Ride'),
      );
    } else if (currentStatus == 'accepted') {
      return ElevatedButton(
        onPressed: () => _updateStatus('en_route'),
        child: const Text('Start Ride'),
      );
    } else if (currentStatus == 'en_route') {
      return ElevatedButton(
        onPressed: () => _updateStatus('completed'),
        child: const Text('Complete Ride'),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (errorMessage != null) {
      return Scaffold(body: Center(child: Text(errorMessage!)));
    }

    final request = ride!['ride_requests'];
    final pickup = LatLng(
      double.parse(request['pickup_lat'].toString()),
      double.parse(request['pickup_lng'].toString()),
    );
    final destination = LatLng(
      double.parse(request['destination_lat'].toString()),
      double.parse(request['destination_lng'].toString()),
    );
    final bounds = LatLngBounds.fromPoints([pickup, destination]);

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Details')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                bounds: bounds,
                boundsOptions: FitBoundsOptions(padding: EdgeInsets.all(32)),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.godavao',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 40,
                      height: 40,
                      point: pickup,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.green,
                      ),
                    ),
                    Marker(
                      width: 40,
                      height: 40,
                      point: destination,
                      child: const Icon(Icons.flag, color: Colors.red),
                    ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, destination],
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passenger: ${request['users']['name'] ?? 'Unknown'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Status: ${ride!['status']}'),
                const SizedBox(height: 16),
                _buildStatusControls(ride!['status']),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
