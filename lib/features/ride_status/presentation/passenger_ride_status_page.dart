import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/chat/presentation/chat_page.dart';

class PassengerRideStatusPage extends StatefulWidget {
  final String rideId;
  const PassengerRideStatusPage({required this.rideId, Key? key})
    : super(key: key);

  @override
  State<PassengerRideStatusPage> createState() =>
      _PassengerRideStatusPageState();
}

class _PassengerRideStatusPageState extends State<PassengerRideStatusPage> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _rideChannel;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _ride;
  String? _matchId;

  @override
  void initState() {
    super.initState();
    _loadRideDetails();
    _subscribeToRideUpdates();
  }

  Future<void> _loadRideDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) load the ride_request
      final rideResp =
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

      if (rideResp == null) {
        throw Exception('Ride not found');
      }
      _ride = Map<String, dynamic>.from(rideResp as Map);

      // 2) load the matching ride_matches row
      final matchResp =
          await _supabase
              .from('ride_matches')
              .select('id')
              .eq('ride_request_id', widget.rideId)
              .maybeSingle();

      if (matchResp == null) {
        throw Exception('No match found for this ride');
      }
      _matchId = (matchResp as Map)['id'] as String;
    } on PostgrestException catch (e) {
      _error = 'Supabase error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _subscribeToRideUpdates() {
    // keep subscription alive to auto‑refresh status
    _rideChannel =
        _supabase
            .channel('ride_requests:${widget.rideId}')
            .onPostgresChanges(
              schema: 'public',
              table: 'ride_requests',
              event: PostgresChangeEvent.update,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: widget.rideId,
              ),
              callback: (payload) {
                final updated = Map<String, dynamic>.from(payload.newRecord!);
                setState(() {
                  _ride = updated;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ride status: ${updated['status']}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            )
            .subscribe();
  }

  @override
  void dispose() {
    if (_rideChannel != null) {
      _supabase.removeChannel(_rideChannel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }

    if (_ride == null || _matchId == null) {
      return const Scaffold(body: Center(child: Text('No ride data')));
    }

    // build map & UI now
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

          // map view
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
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                    Marker(
                      point: dest,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Chat button uses the ride_match.id
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.message),
              label: const Text('Chat with Driver'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(matchId: _matchId!),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
