import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String matchId;

  const PassengerRideStatusPage({super.key, required this.matchId});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  String rideStatus = 'pending';
  String? driverName;
  String? startAddress;
  String? endAddress;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToRideStatus();
    _loadDriverAndRouteInfo();
  }

  /// Listen to real-time updates for ride status
  void _listenToRideStatus() {
    Supabase.instance.client
        .from('ride_matches')
        .stream(primaryKey: ['id'])
        .eq('id', widget.matchId)
        .listen((data) {
          if (data.isNotEmpty) {
            final status = data.first['status'] as String?;
            if (status != null && status != rideStatus) {
              setState(() {
                rideStatus = status;
              });
            }
          }
        });
  }

  /// Fetch driver name and perform reverse geocoding for route
  Future<void> _loadDriverAndRouteInfo() async {
    try {
      final result =
          await Supabase.instance.client
              .from('ride_matches')
              .select('''
            driver_routes(
              users(name),
              start_lat,
              start_lng,
              end_lat,
              end_lng
            )
          ''')
              .eq('id', widget.matchId)
              .maybeSingle();

      if (result != null && result['driver_routes'] != null) {
        final route = result['driver_routes'];

        final driver = route['users']?['name'] ?? 'Unknown Driver';
        final startLat = route['start_lat'];
        final startLng = route['start_lng'];
        final endLat = route['end_lat'];
        final endLng = route['end_lng'];

        final resolvedStart = await _reverseGeocode(startLat, startLng);
        final resolvedEnd = await _reverseGeocode(endLat, endLng);

        setState(() {
          driverName = driver;
          startAddress = resolvedStart;
          endAddress = resolvedEnd;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading route info: $e");
      setState(() => isLoading = false);
    }
  }

  /// Convert lat/lng to readable address
  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return "${place.street}, ${place.subLocality}, ${place.locality}";
      }
    } catch (e) {
      debugPrint("Reverse geocoding failed: $e");
    }
    return 'Unknown location';
  }

  Widget _buildStatusCard(String status) {
    IconData icon;
    Color color;
    String title;
    String description;

    switch (status) {
      case 'pending':
        icon = Icons.hourglass_top;
        color = Colors.orange;
        title = 'Looking for a Driver...';
        description = 'Please wait while we match you with a driver.';
        break;
      case 'accepted':
        icon = Icons.directions_car;
        color = Colors.green;
        title = 'Driver Accepted!';
        description = 'Your driver is on the way to pick you up.';
        break;
      case 'en_route':
        icon = Icons.navigation;
        color = Colors.blue;
        title = 'Ride in Progress';
        description = 'You are now on your way to the destination.';
        break;
      case 'completed':
        icon = Icons.check_circle;
        color = Colors.purple;
        title = 'Ride Completed';
        description = 'You have arrived. Thank you for using GoDavao!';
        break;
      default:
        icon = Icons.error;
        color = Colors.grey;
        title = 'Unknown Status';
        description = 'Unable to determine current ride status.';
    }

    return Card(
      margin: const EdgeInsets.all(24),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverInfo() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (driverName == null || startAddress == null || endAddress == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No driver or route information available.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Driver: $driverName", style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text("Route:", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("From: $startAddress"),
          Text("To: $endAddress"),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Status')),
      body: SingleChildScrollView(
        child: Column(
          children: [_buildDriverInfo(), _buildStatusCard(rideStatus)],
        ),
      ),
    );
  }
}
