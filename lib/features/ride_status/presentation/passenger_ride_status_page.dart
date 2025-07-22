import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String matchId;
  const PassengerRideStatusPage({super.key, required this.matchId});

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? ride;
  LatLng? _driverPos;
  bool loading = true;
  String? errorMessage;
  StreamSubscription<List<Map<String, dynamic>>>? _rideSub;
  StreamSubscription<List<Map<String, dynamic>>>? _locSub;

  @override
  void initState() {
    super.initState();
    _loadRide();
    _rideSub = supabase
        .from('ride_matches')
        .stream(primaryKey: ['id'])
        .eq('id', widget.matchId)
        .listen((_) => _loadRide());
    _locSub = supabase
        .from('driver_locations')
        .stream(primaryKey: ['ride_match_id'])
        .eq('ride_match_id', widget.matchId)
        .listen((rows) {
          if (rows.isNotEmpty) {
            final r = rows.first;
            final lat = r['lat'] as double?;
            final lng = r['lng'] as double?;
            if (lat != null && lng != null) {
              setState(() => _driverPos = LatLng(lat, lng));
            }
          }
        });
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _locSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRide() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final resp =
          await supabase
              .from('ride_matches')
              .select(r'''
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

      if (resp == null || resp['ride_requests'] == null) {
        throw Exception('Ride not found');
      }
      setState(() {
        ride = resp;
        loading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        loading = false;
      });
    }
  }

  Future<String> _rev(double lat, double lng) async {
    try {
      final pm = await placemarkFromCoordinates(lat, lng);
      final p = pm.first;
      return '${p.street}, ${p.locality}';
    } catch (_) {
      return 'Unknown location';
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

    final req = ride!['ride_requests'];
    final pickup = LatLng(
      double.parse(req['pickup_lat'].toString()),
      double.parse(req['pickup_lng'].toString()),
    );
    final dest = LatLng(
      double.parse(req['destination_lat'].toString()),
      double.parse(req['destination_lng'].toString()),
    );
    final bounds = LatLngBounds.fromPoints([pickup, dest]);
    final passenger = req['users']?['name'] as String? ?? 'Unknown';
    final status = ride!['status'] as String;

    return Scaffold(
      appBar: AppBar(title: const Text('Ride Status')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                bounds: bounds,
                boundsOptions: const FitBoundsOptions(
                  padding: EdgeInsets.all(32),
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.godavao',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pickup,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.green,
                      ),
                    ),
                    Marker(
                      point: dest,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.flag, color: Colors.red),
                    ),
                    if (_driverPos != null)
                      Marker(
                        point: _driverPos!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.directions_car,
                          color: Colors.blue,
                        ),
                      ),
                  ],
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [pickup, dest],
                      strokeWidth: 4,
                      color: Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Passenger: $passenger',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Status: ${status.toUpperCase()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
