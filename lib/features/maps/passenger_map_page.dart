import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/features/rides/presentation/confirm_ride_page.dart';

class DriverRoute {
  final String id;
  final String driverId;
  final String polyline;

  DriverRoute.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      driverId = m['driver_id'] as String,
      polyline = m['route_polyline'] as String;
}

class PassengerMapPage extends StatefulWidget {
  const PassengerMapPage({super.key});

  @override
  State<PassengerMapPage> createState() => _PassengerMapPageState();
}

class _PassengerMapPageState extends State<PassengerMapPage> {
  final supabase = Supabase.instance.client;
  final _polyDecoder = PolylinePoints();
  final MapController _map = MapController();

  // Brand tokens (matches your Figma)
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  bool _loadingRoutes = true;
  String? _routesError;

  List<DriverRoute> _routes = [];
  DriverRoute? _selectedRoute;
  List<LatLng> _routePoints = [];

  // OSRM-computed segment for passenger selection
  Polyline? _osrmRoute;

  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loadingRoutes = true;
      _routesError = null;
    });
    try {
      final data = await supabase
          .from('driver_routes')
          .select('id, driver_id, route_polyline');

      _routes =
          (data as List)
              .map((m) => DriverRoute.fromMap(m as Map<String, dynamic>))
              .toList();

      if (_routes.isEmpty) {
        _routesError = 'No active routes right now.';
        setState(() => _loadingRoutes = false);
        return;
      }
      _selectRoute(_routes.first);
    } catch (e) {
      _routesError = 'Error loading routes: $e';
    } finally {
      setState(() => _loadingRoutes = false);
    }
  }

  void _selectRoute(DriverRoute r) {
    final pts = _polyDecoder.decodePolyline(r.polyline);
    _routePoints =
        pts
            .map((p) => LatLng(p.latitude.toDouble(), p.longitude.toDouble()))
            .toList();

    setState(() {
      _selectedRoute = r;
      _pickupLocation = null;
      _dropoffLocation = null;
      _osrmRoute = null;
    });

    if (_routePoints.isNotEmpty) {
      _map.move(_routePoints.first, 13);
    }
  }

  // Tap to snap to nearest segment of the selected route
  void _onMapTap(TapPosition _, LatLng tap) async {
    if (_routePoints.isEmpty) return;

    // Project tap onto nearest segment (quick & robust)
    late LatLng snapped;
    double bestD = double.infinity;
    final dist = const Distance();
    for (var i = 0; i < _routePoints.length - 1; i++) {
      final a = _routePoints[i], b = _routePoints[i + 1];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final len2 = dx * dx + dy * dy;
      if (len2 == 0) continue;
      final t =
          (((tap.longitude - a.longitude) * dx) +
              ((tap.latitude - a.latitude) * dy)) /
          len2;
      final ct = t.clamp(0.0, 1.0);
      final proj = LatLng(a.latitude + ct * dy, a.longitude + ct * dx);
      final d = dist(tap, proj);
      if (d < bestD) {
        bestD = d;
        snapped = proj;
      }
    }

    if (_pickupLocation == null) {
      setState(() => _pickupLocation = snapped);
    } else if (_dropoffLocation == null) {
      setState(() {
        _dropoffLocation = snapped;
        _osrmRoute = null;
      });
      try {
        final fetched = await fetchOsrmRoute(
          start: _pickupLocation!,
          end: _dropoffLocation!,
        );
        setState(() => _osrmRoute = fetched);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Routing failed: $e')));
      }
    } else {
      // Start new selection
      setState(() {
        _pickupLocation = snapped;
        _dropoffLocation = null;
        _osrmRoute = null;
      });
    }
  }

  void _openConfirm() {
    if (_pickupLocation == null ||
        _dropoffLocation == null ||
        _selectedRoute == null) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ConfirmRidePage(
              pickup: _pickupLocation!,
              destination: _dropoffLocation!,
              routeId: _selectedRoute!.id,
              driverId: _selectedRoute!.driverId,
            ),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_loadingRoutes) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Join a Driver Route'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Map
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                center:
                    _routePoints.isNotEmpty
                        ? _routePoints.first
                        : const LatLng(7.19, 125.45),
                zoom: 13,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.godavao.app',
                ),
                // Driver route polyline
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ],
                  ),
                // Passenger segment
                if (_osrmRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _osrmRoute!.points,
                        strokeWidth: 6,
                        color: _purple,
                      ),
                    ],
                  ),
                // Pick & Drop markers
                if (_pickupLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickupLocation!,
                        width: 34,
                        height: 34,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.green,
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                if (_dropoffLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _dropoffLocation!,
                        width: 34,
                        height: 34,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Top route carousel / chips
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 56,
                child:
                    _routesError != null
                        ? _EmptyRoutesBar(
                          message: _routesError!,
                          onRetry: _loadRoutes,
                        )
                        : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          scrollDirection: Axis.horizontal,
                          itemCount: _routes.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final r = _routes[i];
                            final sel = r.id == _selectedRoute?.id;
                            return _RouteChip(
                              index: i + 1,
                              selected: sel,
                              onTap: () => _selectRoute(r),
                            );
                          },
                        ),
              ),
            ),
          ),

          // Bottom sheet: step hints + CTA
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Step helper
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app,
                          size: 18,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _selectedRoute == null
                                ? 'Choose a route to start'
                                : (_pickupLocation == null
                                    ? 'Tap the map to set PICKUP on the route'
                                    : (_dropoffLocation == null
                                        ? 'Tap again to set DROPOFF'
                                        : 'Tap once more to change PICKUP')),
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Small status row (pill chips)
                    Row(
                      children: [
                        _Pill(
                          icon: Icons.alt_route,
                          label:
                              _selectedRoute == null
                                  ? 'Route: —'
                                  : 'Route: ${_routes.indexWhere((r) => r.id == _selectedRoute!.id) + 1}',
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          icon: Icons.location_pin,
                          label:
                              _pickupLocation == null
                                  ? 'Pickup: —'
                                  : 'Pickup set',
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          icon: Icons.flag,
                          label:
                              _dropoffLocation == null
                                  ? 'Dropoff: —'
                                  : 'Dropoff set',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Primary CTA (gradient button)
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [_purple, _purpleDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withOpacity(0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed:
                              (_pickupLocation != null &&
                                      _dropoffLocation != null &&
                                      !_sending)
                                  ? _openConfirm
                                  : null,
                          child:
                              _sending
                                  ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Text(
                                    'Review Fare',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Small UI widgets ----------

class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  static const _purple = Color(0xFF6A27F7);

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Route $index',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
      selected: selected,
      selectedColor: _purple,
      backgroundColor: Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? _purple : Colors.black12),
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoutesBar extends StatelessWidget {
  const _EmptyRoutesBar({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}
