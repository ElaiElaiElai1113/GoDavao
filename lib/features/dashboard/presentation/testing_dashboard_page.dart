import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestingDashboardPage extends StatefulWidget {
  const TestingDashboardPage({super.key});

  @override
  State<TestingDashboardPage> createState() => _TestingDashboardPageState();
}

class _TestingDashboardPageState extends State<TestingDashboardPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _rideRequests = [];
  List<Map<String, dynamic>> _rideMatches = [];

  Future<void> _fetchData() async {
    final rideRes = await _client.from('ride_requests').select();
    final matchRes = await _client
        .from('ride_matches')
        .select('*, ride_requests(*)');
    setState(() {
      _rideRequests = rideRes;
      _rideMatches = matchRes;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Testing Dashboard')),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '🧍 Ride Requests',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ..._rideRequests.map(
              (ride) => ListTile(
                title: Text(
                  'Pickup: ${ride['pickup_lat']}, ${ride['pickup_lng']}',
                ),
                subtitle: Text(
                  'Dest: ${ride['destination_lat']}, ${ride['destination_lng']}',
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '✅ Ride Matches',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ..._rideMatches.map(
              (match) => ListTile(
                title: Text('Match ID: ${match['id']}'),
                subtitle: Text(
                  'RideReq: ${match['ride_requests']['pickup_lat']} → ${match['ride_requests']['destination_lat']}\n'
                  'Driver: ${match['driver_routes']['start_lat']} → ${match['driver_routes']['end_lat']}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
