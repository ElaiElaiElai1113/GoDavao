// lib/features/ride_status/presentation/driver_ride_status_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class DriverRideStatusPage extends StatefulWidget {
  final String rideId;
  const DriverRideStatusPage({required this.rideId, Key? key})
    : super(key: key);

  @override
  _DriverRideStatusPageState createState() => _DriverRideStatusPageState();
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data =
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
              .single();

      if (data == null) {
        throw Exception('Ride not found or missing request info');
      }

      setState(() {
        _ride = Map<String, dynamic>.from(data as Map);
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Supabase error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Details')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('Error: $_error'))
              : _ride == null
              ? const Center(child: Text('No ride data'))
              : _buildRideView(),
    );
  }

  Widget _buildRideView() {
    final r = _ride!;
    final pickup = LatLng(r['pickup_lat'], r['pickup_lng']);
    final dest = LatLng(r['destination_lat'], r['destination_lng']);

    return Column(
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
              // base map tiles
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),

              // route polyline
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [pickup, dest],
                    strokeWidth: 4,
                    // omit color to use default or let the theme pick it
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),

              // pickup & destination markers
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
    );
  }
}
