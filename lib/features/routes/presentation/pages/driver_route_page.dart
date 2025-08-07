// lib/features/routes/presentation/pages/driver_route_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// our OSRM helper from earlier
import 'package:godavao/core/osrm_service.dart';
// for encoding back into a Google polyline string
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;

// import the global notifications instance
import 'package:godavao/main.dart' show localNotify;

class DriverRoutePage extends StatefulWidget {
  const DriverRoutePage({super.key});
  @override
  State<DriverRoutePage> createState() => _DriverRoutePageState();
}

class _DriverRoutePageState extends State<DriverRoutePage> {
  final MapController _mapController = MapController();

  LatLng? _start;
  LatLng? _end;
  Polyline? _route; // the OSRM-computed route
  bool _publishing = false;
  String? _error;

  /// Long-press to pick start/end/reset
  void _onMapLongPress(TapPosition _, LatLng latlng) async {
    if (_start == null) {
      // first long-press = start
      setState(() {
        _start = latlng;
        _end = null;
        _route = null;
        _error = null;
      });
      return;
    }
    if (_end == null) {
      // second long-press = end, now fetch OSRM
      setState(() => _end = latlng);
      try {
        final fetched = await fetchOsrmRoute(start: _start!, end: _end!);
        setState(() => _route = fetched);
      } catch (e) {
        setState(() => _error = 'Routing failed: $e');
      }
      return;
    }
    // third long-press = reset start
    setState(() {
      _start = latlng;
      _end = null;
      _route = null;
      _error = null;
    });
  }

  Future<void> _publishRoute() async {
    if (_route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick start & end first.')),
      );
      return;
    }
    setState(() => _publishing = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Not signed in';

      // encode OSRM LatLngs to a polyline string
      // gpa.encodePolyline wants List<List<double>> in [lat, lng] order
      final coords =
          _route!.points.map((p) => [p.latitude, p.longitude]).toList();
      final encoded = gpa.encodePolyline(coords);

      // save to Supabase
      await Supabase.instance.client.from('driver_routes').insert({
        'driver_id': user.id,
        'route_polyline': encoded,
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Route published!')));
      await localNotify.show(
        0,
        'Route Published',
        'Your driver route has been published.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'routes_channel',
            'Route Alerts',
            channelDescription: 'Notifications for route publishing',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );

      // clear for next draw
      setState(() {
        _start = null;
        _end = null;
        _route = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Publish failed: $e');
    } finally {
      setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draw & Publish Driver Route')),
      body: Column(
        children: [
          if (_error != null)
            Container(
              color: Colors.red.shade100,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _start ?? LatLng(7.1907, 125.4553),
                zoom: 13,
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourcompany.godavao',
                ),
                // OSRM polyline in blue
                if (_route != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _route!.points,
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                // start marker
                if (_start != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _start!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                // end marker
                if (_end != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _end!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              icon:
                  _publishing
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.publish),
              label: Text(_publishing ? 'Publishing…' : 'Publish Route'),
              onPressed: _publishing ? null : _publishRoute,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
