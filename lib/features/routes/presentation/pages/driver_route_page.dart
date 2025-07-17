import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/features/routes/data/driver_route_service.dart';
import 'package:godavao/features/routes/models/driver_route_model.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverRoutePage extends StatefulWidget {
  const DriverRoutePage({super.key});

  @override
  State<DriverRoutePage> createState() => _DriverRoutePageState();
}

class _DriverRoutePageState extends State<DriverRoutePage> {
  final LatLng _davaoCenter = LatLng(7.1907, 125.4553);
  LatLng? _startLocation;
  LatLng? _endLocation;

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      if (_startLocation == null) {
        _startLocation = latlng;
      } else if (_endLocation == null) {
        _endLocation = latlng;
      } else {
        _startLocation = latlng;
        _endLocation = null;
      }
    });
  }

  Future<void> _saveRoute() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _startLocation == null || _endLocation == null) return;

    final route = DriverRoute(
      driverId: user.id,
      startLat: _startLocation!.latitude,
      startLng: _startLocation!.longitude,
      endLat: _endLocation!.latitude,
      endLng: _endLocation!.longitude,
    );

    try {
      await DriverRouteService().saveRoute(route);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Route saved successfully")));
      setState(() {
        _startLocation = null;
        _endLocation = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Define Your Route')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              center: _davaoCenter,
              zoom: 13.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.godavao',
              ),
              if (_startLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _startLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.green,
                      ),
                    ),
                    if (_endLocation != null)
                      Marker(
                        point: _endLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.flag, color: Colors.red),
                      ),
                  ],
                ),
              if (_startLocation != null && _endLocation != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_startLocation!, _endLocation!],
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
            ],
          ),
          if (_startLocation != null && _endLocation != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _saveRoute,
                child: const Text("Save Route"),
              ),
            ),
        ],
      ),
    );
  }
}
