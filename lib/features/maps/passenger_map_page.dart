import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';

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
  final Distance _dist = const Distance();
  final _destCtrl = TextEditingController();

  // Brand tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  // Map readiness guard
  bool _mapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;

  // Data
  bool _loading = false;
  String? _error;

  LatLng? _destination;
  List<DriverRoute> _allRoutes = []; // raw from DB
  List<DriverRoute> _candidateRoutes = []; // after destination search
  DriverRoute? _selectedRoute;

  List<LatLng> _selectedRoutePoints = [];
  Polyline? _osrmSegment; // from pickup → destination

  LatLng? _pickup;

  // Config
  static const double _matchRadiusMeters =
      600; // how close destination must be to a route

  @override
  void initState() {
    super.initState();
    _primeRoutes();
  }

  @override
  void dispose() {
    _destCtrl.dispose();
    super.dispose();
  }

  Future<void> _primeRoutes() async {
    // Preload driver routes once (we filter client-side by destination)
    try {
      final data = await supabase
          .from('driver_routes')
          .select('id, driver_id, route_polyline')
          .eq('is_active', true); // optional if you have this column

      _allRoutes =
          (data as List)
              .map((m) => DriverRoute.fromMap(m as Map<String, dynamic>))
              .toList();
      setState(() {}); // nothing shown until user searches
    } catch (e) {
      // Non-fatal — search can retry
    }
  }

  void _safeMove(LatLng center, double zoom) {
    if (!mounted) return;
    if (_mapReady) {
      _map.move(center, zoom);
    } else {
      _pendingCenter = center;
      _pendingZoom = zoom;
    }
  }

  Future<void> _searchByAddress(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _destination = null;
      _candidateRoutes = [];
      _selectedRoute = null;
      _selectedRoutePoints = [];
      _pickup = null;
      _osrmSegment = null;
    });

    try {
      final results = await locationFromAddress(text);
      if (results.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Destination not found. Try a more specific address.';
        });
        return;
      }
      final dest = LatLng(results.first.latitude, results.first.longitude);
      _destination = dest;
      _safeMove(dest, 14);

      // Now filter routes that pass near destination
      final matches = <DriverRoute>[];
      for (final r in _allRoutes) {
        final pts =
            _polyDecoder
                .decodePolyline(r.polyline)
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList();
        if (_isPointNearPolyline(dest, pts, _matchRadiusMeters)) {
          matches.add(r);
        }
      }

      if (matches.isEmpty) {
        setState(() {
          _loading = false;
          _candidateRoutes = [];
          _error = 'No active routes pass near that destination.';
        });
        return;
      }

      setState(() {
        _candidateRoutes = matches;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  bool _isPointNearPolyline(LatLng p, List<LatLng> polyline, double maxMeters) {
    if (polyline.length < 2) return false;
    double best = double.infinity;

    for (var i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final d = _distancePointToSegmentMeters(p, a, b);
      if (d < best) best = d;
      if (best <= maxMeters) return true;
    }
    return best <= maxMeters;
  }

  // Approximate perpendicular distance from point P to segment AB (meters)
  double _distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    // Project using simple lat/lng plane (good enough for small spans),
    // then convert distances with haversine for endpoints
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final vx = bx - ax, vy = by - ay;
    final wx = px - ax, wy = py - ay;

    final c1 = vx * wx + vy * wy;
    if (c1 <= 0) return _dist(a, p);

    final c2 = vx * vx + vy * vy;
    if (c2 <= c1) return _dist(b, p);

    final t = c1 / c2;
    final proj = LatLng(ay + t * vy, ax + t * vx);
    return _dist(proj, p);
  }

  // When the user picks a candidate route
  void _selectRoute(DriverRoute r) {
    final pts =
        _polyDecoder
            .decodePolyline(r.polyline)
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

    setState(() {
      _selectedRoute = r;
      _selectedRoutePoints = pts;
      _pickup = null;
      _osrmSegment = null;
    });

    if (pts.isNotEmpty) {
      _safeMove(pts.first, 13);
    }
  }

  // Tap on the map:
  // - If we have a selected route and destination, we interpret as setting/adjusting pickup.
  void _onMapTap(TapPosition _, LatLng tap) async {
    if (_selectedRoutePoints.isEmpty || _destination == null) return;

    // Snap pickup to nearest segment of the selected route
    final snapped = _snapToPolyline(tap, _selectedRoutePoints);
    setState(() {
      _pickup = snapped;
      _osrmSegment = null;
    });

    try {
      final seg = await fetchOsrmRoute(start: snapped, end: _destination!);
      if (!mounted) return;
      setState(() => _osrmSegment = seg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Routing failed: $e')));
    }
  }

  LatLng _snapToPolyline(LatLng p, List<LatLng> polyline) {
    late LatLng best;
    double bestD = double.infinity;

    for (var i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final d = _distancePointToSegmentMeters(p, a, b);

      if (d < bestD) {
        bestD = d;
        // compute projection again to get the closest LatLng
        final ax = a.longitude, ay = a.latitude;
        final bx = b.longitude, by = b.latitude;
        final px = p.longitude, py = p.latitude;

        final vx = bx - ax, vy = by - ay;
        final wx = px - ax, wy = py - ay;

        final c1 = vx * wx + vy * wy;
        final c2 = vx * vx + vy * vy;

        LatLng proj;
        if (c1 <= 0) {
          proj = a;
        } else if (c2 <= c1) {
          proj = b;
        } else {
          final t = c1 / c2;
          proj = LatLng(ay + t * vy, ax + t * vx);
        }
        best = proj;
      }
    }
    return best;
  }

  void _openConfirm() {
    if (_pickup == null || _destination == null || _selectedRoute == null) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ConfirmRidePage(
              pickup: _pickup!,
              destination: _destination!,
              routeId: _selectedRoute!.id,
              driverId: _selectedRoute!.driverId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDest = _destination != null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Find a Route to Your Destination'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _SearchBar(
              controller: _destCtrl,
              onSubmit: _searchByAddress,
              onClear: () {
                setState(() {
                  _destination = null;
                  _candidateRoutes = [];
                  _selectedRoute = null;
                  _selectedRoutePoints = [];
                  _pickup = null;
                  _osrmSegment = null;
                  _error = null;
                });
              },
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Map
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                center: const LatLng(7.19, 125.45),
                zoom: 12.5,
                onTap: _onMapTap,
                onMapReady: () {
                  if (!mounted) return;
                  setState(() => _mapReady = true);
                  if (_pendingCenter != null) {
                    _map.move(
                      _pendingCenter!,
                      _pendingZoom ?? _map.camera.zoom,
                    );
                    _pendingCenter = null;
                    _pendingZoom = null;
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.godavao.app',
                ),

                // Selected driver route polyline
                if (_selectedRoutePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _selectedRoutePoints,
                        strokeWidth: 5,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ],
                  ),

                // Passenger OSRM segment (pickup → destination)
                if (_osrmSegment != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _osrmSegment!.points,
                        strokeWidth: 6,
                        color: _purple,
                      ),
                    ],
                  ),

                // Destination marker
                if (_destination != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _destination!,
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

                // Pickup marker
                if (_pickup != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickup!,
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
              ],
            ),
          ),

          // Candidate routes carousel when destination is set
          if (hasDest)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 60,
                  child:
                      _loading
                          ? const _LoadingBar()
                          : _error != null
                          ? _EmptyRoutesBar(
                            message: _error!,
                            onRetry: () => _searchByAddress(_destCtrl.text),
                          )
                          : _candidateRoutes.isEmpty
                          ? _EmptyRoutesBar(
                            message: 'No routes match your destination.',
                            onRetry: () => _searchByAddress(_destCtrl.text),
                          )
                          : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            scrollDirection: Axis.horizontal,
                            itemCount: _candidateRoutes.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final r = _candidateRoutes[i];
                              final sel = r.id == _selectedRoute?.id;
                              return _RouteChip(
                                label: 'Route ${i + 1}',
                                selected: sel,
                                onTap: () => _selectRoute(r),
                              );
                            },
                          ),
                ),
              ),
            ),

          // Bottom sheet
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
                            _destination == null
                                ? 'Type an address to find matching driver routes'
                                : _selectedRoute == null
                                ? 'Pick a route above'
                                : _pickup == null
                                ? 'Tap the map to set your PICKUP on this route'
                                : 'Tap the map again to adjust your pickup',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Status pills
                    Row(
                      children: [
                        _Pill(
                          icon: Icons.flag,
                          label:
                              _destination == null
                                  ? 'Destination: —'
                                  : 'Destination set',
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          icon: Icons.alt_route,
                          label:
                              _selectedRoute == null
                                  ? 'Route: —'
                                  : 'Route selected',
                        ),
                        const SizedBox(width: 8),
                        _Pill(
                          icon: Icons.location_pin,
                          label: _pickup == null ? 'Pickup: —' : 'Pickup set',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // CTA
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
                              offset: Offset(0, 8),
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
                              (_pickup != null &&
                                      _destination != null &&
                                      _selectedRoute != null)
                                  ? _openConfirm
                                  : null,
                          child: const Text(
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

/* ---------------- Small UI widgets ---------------- */

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final void Function(String) onSubmit;
  final VoidCallback onClear;

  static const _purple = Color(0xFF6A27F7);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter your destination',
              ),
              onSubmitted: onSubmit,
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close, color: Colors.black45),
              onPressed: () {
                controller.clear();
                onClear();
              },
            ),
          FilledButton(
            onPressed: () => onSubmit(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _purple = Color(0xFF6A27F7);

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
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

class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        SizedBox(width: 12),
        Expanded(child: LinearProgressIndicator(minHeight: 6)),
        SizedBox(width: 12),
      ],
    );
  }
}
