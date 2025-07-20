// lib/features/ride_status/presentation/driver_rides_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'driver_ride_status_page.dart';

class DriverRidesPage extends StatefulWidget {
  const DriverRidesPage({Key? key}) : super(key: key);

  @override
  State<DriverRidesPage> createState() => _DriverRidesPageState();
}

class _DriverRidesPageState extends State<DriverRidesPage> {
  final supabase = Supabase.instance.client;
  final _poly = PolylinePoints();

  List<Map<String, dynamic>> _ongoing = [];
  List<Map<String, dynamic>> _completed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    // 1) Get this driver's most recent route (with its id)
    final routeData =
        await supabase
            .from('driver_routes')
            .select('id, route_polyline')
            .eq('driver_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (routeData == null) {
      // No route published yet
      setState(() {
        _ongoing = [];
        _completed = [];
        _loading = false;
      });
      return;
    }

    final routeId = routeData['id'] as String;
    final encoded = routeData['route_polyline'] as String;
    final pts =
        _poly
            .decodePolyline(encoded)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

    // 2) Fetch all matches on this route
    final matches = await supabase
        .from('ride_matches')
        .select(r'''
      id,
      status,
      ride_requests(pickup_lat, pickup_lng, users(name)),
      created_at
    ''')
        .eq('driver_route_id', routeId)
        .order('created_at', ascending: true);

    // 3) Enrich & sort by nearest index along route
    final dist = Distance();
    final enriched = <Map<String, dynamic>>[];
    for (final m in matches) {
      final req = m['ride_requests'];
      final lat = double.parse(req['pickup_lat'].toString());
      final lng = double.parse(req['pickup_lng'].toString());
      final pick = LatLng(lat, lng);

      int bestI = 0;
      double bestD = double.infinity;
      for (int i = 0; i < pts.length; i++) {
        final d = dist(pts[i], pick);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }

      enriched.add({
        'id': m['id'],
        'status': m['status'],
        'created_at': m['created_at'],
        'passenger': req['users']?['name'] ?? 'Unknown',
        'pickup_point': pick,
        'route_index': bestI,
      });
    }

    enriched.sort((a, b) => a['route_index'].compareTo(b['route_index']));

    final ongoing = enriched.where((e) => e['status'] != 'completed').toList();
    final completed =
        enriched.where((e) => e['status'] == 'completed').toList();

    if (!mounted) return;
    setState(() {
      _ongoing = ongoing;
      _completed = completed;
      _loading = false;
    });
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
        return Colors.grey;
      case 'accepted':
        return Colors.blue;
      case 'en_route':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      default:
        return Colors.black;
    }
  }

  Widget _card(Map<String, dynamic> m) {
    final dt = DateFormat(
      'MMM d, y h:mm a',
    ).format(DateTime.parse(m['created_at']));
    return Card(
      child: ListTile(
        title: Text("Pickup: ${m['passenger']}"),
        subtitle: Text(dt),
        trailing: Text(
          m['status'].toUpperCase(),
          style: TextStyle(
            color: _statusColor(m['status']),
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DriverRideStatusPage(rideId: m['id']),
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pickups on My Route')),
      body: RefreshIndicator(
        onRefresh: _loadMatches,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Upcoming Pickups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._ongoing.map(_card),
            const Divider(),
            const Text(
              'Completed Pickups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._completed.map(_card),
          ],
        ),
      ),
    );
  }
}
