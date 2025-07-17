import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/ride_status/presentation/passenger_ride_status_page.dart';

class PassengerRidesPage extends StatefulWidget {
  const PassengerRidesPage({super.key});

  @override
  State<PassengerRidesPage> createState() => _PassengerRidesPageState();
}

class _PassengerRidesPageState extends State<PassengerRidesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> ongoingRides = [];
  List<Map<String, dynamic>> pastRides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchRides();
  }

  Future<void> fetchRides() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('ride_requests')
        .select()
        .eq('passenger_id', user.id)
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> ongoing = [];
    List<Map<String, dynamic>> past = [];

    for (final ride in data) {
      final status = ride['status'];
      final pickup = await reverseGeocode(
        ride['pickup_lat'],
        ride['pickup_lng'],
      );
      final destination = await reverseGeocode(
        ride['destination_lat'],
        ride['destination_lng'],
      );

      final enriched = {
        ...ride,
        'pickup_address': pickup,
        'destination_address': destination,
      };

      if (status == 'completed' || status == 'cancelled') {
        past.add(enriched);
      } else {
        ongoing.add(enriched);
      }
    }

    if (!mounted) return;
    setState(() {
      ongoingRides = ongoing;
      pastRides = past;
      loading = false;
    });
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      final place = placemarks.first;
      return '${place.street}, ${place.locality}';
    } catch (_) {
      return 'Unknown location';
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.grey;
      case 'accepted':
        return Colors.blue;
      case 'en_route':
        return Colors.orange;
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
    final createdAt = DateTime.parse(ride['created_at']);
    final date = DateFormat('MMM d, y h:mm a').format(createdAt);

    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(
          '${ride['pickup_address']} → ${ride['destination_address']}',
        ),
        subtitle: Text(date),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );

    // Make card tappable only for ongoing rides
    if (status == 'pending' || status == 'accepted' || status == 'en_route') {
      return InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => PassengerRideStatusPage(rideRequestId: ride['id']),
            ),
          );
        },
        child: card,
      );
    } else {
      return card;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Rides")),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: fetchRides,
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
                      "Ride History",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...pastRides.map(rideCard),
                  ],
                ),
              ),
    );
  }
}
