import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'driver_ride_status_page.dart';

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({super.key});

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> ongoingRides = [];
  List<Map<String, dynamic>> completedRides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadDriverMatches();
  }

  Future<void> _loadDriverMatches() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    try {
      final response = await supabase
          .from('ride_matches')
          .select('''
            id,
            status,
            created_at,
            ride_requests(
              pickup_lat,
              pickup_lng,
              destination_lat,
              destination_lng,
              users(name)
            )
          ''')
          .eq('driver_id', user.id)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> ongoing = [];
      List<Map<String, dynamic>> completed = [];

      for (final ride in response) {
        final request = ride['ride_requests'];
        final pickupLat = request['pickup_lat'];
        final pickupLng = request['pickup_lng'];
        final destinationLat = request['destination_lat'];
        final destinationLng = request['destination_lng'];

        final pickup = await _reverseGeocode(pickupLat, pickupLng);
        final destination = await _reverseGeocode(
          destinationLat,
          destinationLng,
        );

        final rideData = {
          'id': ride['id'],
          'status': ride['status'],
          'created_at': ride['created_at'],
          'passenger': request['users']?['name'] ?? 'Unknown',
          'pickup_address': pickup,
          'destination_address': destination,
          'pickup_latlng': LatLng(pickupLat, pickupLng),
          'destination_latlng': LatLng(destinationLat, destinationLng),
        };

        if (ride['status'] == 'completed') {
          completed.add(rideData);
        } else {
          ongoing.add(rideData);
        }
      }

      if (!mounted) return;
      setState(() {
        ongoingRides = ongoing;
        completedRides = completed;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error loading driver matches: $e");
      setState(() => loading = false);
    }
  }

  Future<String> _reverseGeocode(dynamic lat, dynamic lng) async {
    try {
      final latDouble = lat is double ? lat : double.tryParse(lat.toString());
      final lngDouble = lng is double ? lng : double.tryParse(lng.toString());

      if (latDouble == null || lngDouble == null) return 'Unknown location';

      final placemarks = await placemarkFromCoordinates(latDouble, lngDouble);
      final place = placemarks.first;
      return "${place.street}, ${place.locality}";
    } catch (_) {
      return 'Unknown location';
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.grey;
      case 'accepted':
        return Colors.amber;
      case 'en_route':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.black;
    }
  }

  Widget rideCard(Map<String, dynamic> ride) {
    final status = ride['status'];
    final date = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(ride['created_at']));
    final pickupLatLng = ride['pickup_latlng'];
    final destLatLng = ride['destination_latlng'];

    if (pickupLatLng == null || destLatLng == null) {
      return const SizedBox.shrink();
    }

    final mapPreview = SizedBox(
      height: 120,
      child: FlutterMap(
        options: MapOptions(
          center: LatLng(
            (pickupLatLng.latitude + destLatLng.latitude) / 2,
            (pickupLatLng.longitude + destLatLng.longitude) / 2,
          ),
          zoom: 13,
          interactiveFlags: InteractiveFlag.none,
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
                point: pickupLatLng,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.green,
                  size: 30,
                ),
              ),
              Marker(
                width: 40,
                height: 40,
                point: destLatLng,
                child: const Icon(Icons.flag, color: Colors.red, size: 30),
              ),
            ],
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: [pickupLatLng, destLatLng],
                color: Colors.blue,
                strokeWidth: 4,
              ),
            ],
          ),
        ],
      ),
    );

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverRideStatusPage(matchId: ride['id']),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mapPreview,
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${ride['pickup_address']} → ${ride['destination_address']}",
                  ),
                  const SizedBox(height: 4),
                  Text("Passenger: ${ride['passenger']}"),
                  Text(date),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor(status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor(status),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Ride Matches')),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadDriverMatches,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (ongoingRides.isNotEmpty) ...[
                      const Text(
                        "Ongoing Rides",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...ongoingRides.map(rideCard),
                      const Divider(),
                    ],
                    const Text(
                      "Completed Rides",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...completedRides.map(rideCard),
                  ],
                ),
              ),
    );
  }
}
