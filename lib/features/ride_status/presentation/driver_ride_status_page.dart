import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({super.key});

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> matchedRides = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchMatchedRides();
  }

  Future<void> fetchMatchedRides() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('ride_matches')
        .select(
          'id, ride_requests(id, pickup_lat, pickup_lng, destination_lat, destination_lng, status)',
        )
        .eq('driver_id', user.id);

    setState(() {
      matchedRides = List<Map<String, dynamic>>.from(response);
      loading = false;
    });
  }

  Future<void> updateRideStatus(String rideRequestId, String newStatus) async {
    await supabase
        .from('ride_requests')
        .update({'status': newStatus})
        .eq('id', rideRequestId);
    fetchMatchedRides();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Driver Rides")),
      body: ListView.builder(
        itemCount: matchedRides.length,
        itemBuilder: (context, index) {
          final ride = matchedRides[index]['ride_requests'];
          final status = ride['status'];
          final rideId = ride['id'];

          return Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: Text(
                'Pickup: ${ride['pickup_lat']}, ${ride['pickup_lng']}',
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Destination: ${ride['destination_lat']}, ${ride['destination_lng']}',
                  ),
                  Text('Status: $status'),
                ],
              ),
              trailing: Column(
                children: [
                  if (status == 'pending')
                    ElevatedButton(
                      onPressed: () => updateRideStatus(rideId, 'accepted'),
                      child: const Text('Accept'),
                    ),
                  if (status == 'accepted')
                    ElevatedButton(
                      onPressed: () => updateRideStatus(rideId, 'in_progress'),
                      child: const Text('Start Ride'),
                    ),
                  if (status == 'in_progress')
                    ElevatedButton(
                      onPressed: () => updateRideStatus(rideId, 'completed'),
                      child: const Text('Complete'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
