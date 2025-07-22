import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, super.key});

  @override
  State<DriverRideStatusPage> createState() => _DriverRideStatusPageState();
}

class _DriverRideStatusPageState extends State<DriverRideStatusPage> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _ride;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRideDetails();
  }

  Future<void> _loadRideDetails() async {
    setState(() => _loading = true);

    try {
      final resp =
          await _supabase
              .from('ride_requests')
              .select('''
            id,
            pickup_lat,
            pickup_lng,
            destination_lat,
            destination_lng,
            status,
            driver_route_id
          ''')
              .eq('id', widget.rideId)
              .maybeSingle();

      if (resp == null) {
        setState(() {
          _error = 'Ride not found for id: ${widget.rideId}';
          _loading = false;
        });
        return;
      }

      setState(() {
        _ride = Map<String, dynamic>.from(resp as Map);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Supabase error: ${e.message}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    if (_ride == null) {
      return const Scaffold(body: Center(child: Text('No ride data')));
    }

    final r = _ride!;
    final pickup = LatLng(r['pickup_lat'], r['pickup_lng']);
    final dest = LatLng(r['destination_lat'], r['destination_lng']);

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Details')),
      body: Column(
        children: [
          ListTile(
            title: Text('Status: ${r['status']}'),
            subtitle: Text(
              'Driver route: ${r['driver_route_id'] ?? 'unassigned'}',
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(center: pickup, zoom: 13),

              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.godavao',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, dest],
                      strokeWidth: 4,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.green,
                      ),
                    ),
                    Marker(
                      point: dest,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
