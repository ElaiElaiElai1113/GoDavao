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

    // 1) get latest driver_route for this driver
    final routeData =
        await supabase
            .from('driver_routes')
            .select('id, route_polyline')
            .eq('driver_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (routeData == null) {
      _ongoing = [];
      _completed = [];
      setState(() => _loading = false);
      return;
    }

    final routeId = routeData['id'] as String;
    final pts =
        _poly
            .decodePolyline(routeData['route_polyline'] as String)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

    // 2) fetch all ride_matches on that route, include ride_request_id
    final raw = await supabase
        .from('ride_matches')
        .select(r'''
          id,
          ride_request_id,
          status,
          created_at,
          ride_requests (
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng
          ),
          users!ride_matches_driver_id_fkey(name)
        ''')
        .eq('driver_route_id', routeId)
        .order('created_at', ascending: true);

    // 3) enrich & drop any with null ride_request_id
    final dist = Distance();
    final enriched = <Map<String, dynamic>>[];
    for (var m in raw as List) {
      final reqId = m['ride_request_id'] as String?;
      if (reqId == null) continue; // skip null!

      final rideReq = m['ride_requests'] as Map<String, dynamic>;
      final pickPt = LatLng(
        rideReq['pickup_lat'] as double,
        rideReq['pickup_lng'] as double,
      );

      // nearest index on route
      int bestI = 0;
      double bestD = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        final d = dist(pts[i], pickPt);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }

      enriched.add({
        'route_index': bestI,
        'ride_request_id': reqId, // safe now
        'status': m['status'],
        'created_at': m['created_at'],
        'passenger': (m['users'] as Map)['name'] ?? 'Unknown',
      });
    }

    enriched.sort((a, b) => a['route_index'].compareTo(b['route_index']));
    _ongoing = enriched.where((e) => e['status'] != 'completed').toList();
    _completed = enriched.where((e) => e['status'] == 'completed').toList();

    setState(() => _loading = false);
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
    ).format(DateTime.parse(m['created_at'] as String));
    return Card(
      child: ListTile(
        title: Text("Pickup: ${m['passenger']}"),
        subtitle: Text(dt),
        trailing: Text(
          (m['status'] as String).toUpperCase(),
          style: TextStyle(
            color: _statusColor(m['status'] as String),
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => DriverRideStatusPage(
                    rideId: m['ride_request_id'] as String,
                  ),
            ),
          );
        },
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
