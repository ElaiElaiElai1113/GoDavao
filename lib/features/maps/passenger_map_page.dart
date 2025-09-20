import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart'; // <-- NEW

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/features/rides/presentation/confirm_ride_page.dart';

/// Data model for driver route listing. We support both OSRM and manual routes.
class DriverRoute {
  final String id;
  final String driverId;
  final String? routeMode; // 'osrm' | 'manual' | null
  final String? routePolyline; // encoded OSRM line
  final String? manualPolyline; // encoded manual line

  DriverRoute.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      driverId = m['driver_id'] as String,
      routeMode = (m['route_mode'] as String?),
      routePolyline = (m['route_polyline'] as String?),
      manualPolyline = (m['manual_polyline'] as String?);
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
  final Distance _distance = const Distance();

  // destination search input
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

  LatLng? _searchedDestination; // result of text search (for filtering)
  List<DriverRoute> _allRoutes = []; // raw from DB
  List<DriverRoute> _candidateRoutes = []; // after destination search
  DriverRoute? _selectedRoute;

  List<LatLng> _selectedRoutePoints = [];

  // Passenger chosen points (snapped to route)
  LatLng? _pickup;
  LatLng? _dropoff;

  // OSRM for chosen pickup→dropoff
  Polyline? _osrmSegment;

  // which point the “Edit” button should change next
  String _editTarget = 'auto'; // 'pickup' | 'dropoff' | 'auto'

  // Config
  static const double _matchRadiusMeters = 600; // route near destination

  // ---------- NEW: live user location ----------
  StreamSubscription<Position>? _posSub;
  LatLng? _me;
  double? _meAccuracy; // meters
  bool _followMe = false;

  @override
  void initState() {
    super.initState();
    _primeRoutes();
    _startLiveLocation(); // <-- NEW
  }

  @override
  void dispose() {
    _posSub?.cancel(); // <-- NEW
    _destCtrl.dispose();
    super.dispose();
  }

  /* ----------------------------- Data loading ----------------------------- */

  Future<void> _primeRoutes() async {
    try {
      final data = await supabase
          .from('driver_routes')
          .select('id, driver_id, route_mode, route_polyline, manual_polyline')
          .eq('is_active', true);
      _allRoutes =
          (data as List)
              .map((m) => DriverRoute.fromMap(m as Map<String, dynamic>))
              .toList();
      if (mounted) setState(() {});
    } catch (_) {
      // non-fatal; we’ll surface errors during search
    }
  }

  /* ----------------------------- Map helpers ----------------------------- */

  void _safeMove(LatLng center, double zoom) {
    if (!mounted) return;
    if (_mapReady) {
      _map.move(center, zoom);
    } else {
      _pendingCenter = center;
      _pendingZoom = zoom;
    }
  }

  // Decode whichever polyline is appropriate (manual > route if mode says so)
  List<LatLng> _decodeEffectivePolyline(DriverRoute r) {
    String? encoded;
    if (r.routeMode == 'manual') {
      encoded = r.manualPolyline ?? r.routePolyline;
    } else if (r.routeMode == 'osrm') {
      encoded = r.routePolyline ?? r.manualPolyline;
    } else {
      // missing mode: pick whichever is available
      encoded = r.routePolyline ?? r.manualPolyline;
    }
    if (encoded == null || encoded.isEmpty) return const [];

    final pts = _polyDecoder.decodePolyline(encoded);
    return pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  // Meter distance using latlong2 Distance
  double _meters(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

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

  // Approx perpendicular distance P→AB in meters
  double _distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final vx = bx - ax, vy = by - ay;
    final wx = px - ax, wy = py - ay;

    final c1 = vx * wx + vy * wy;
    if (c1 <= 0) return _meters(a, p);

    final c2 = vx * vx + vy * vy;
    if (c2 <= c1) return _meters(b, p);

    final t = c1 / c2;
    final proj = LatLng(ay + t * vy, ax + t * vx);
    return _meters(proj, p);
  }

  LatLng _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude, ay = a.latitude;
    final bx = b.longitude, by = b.latitude;
    final px = p.longitude, py = p.latitude;

    final vx = bx - ax, vy = by - ay;
    final wx = px - ax, wy = py - ay;

    final c1 = vx * wx + vy * wy;
    final c2 = vx * vx + vy * vy;

    if (c1 <= 0) return a;
    if (c2 <= c1) return b;

    final t = c1 / c2;
    return LatLng(ay + t * vy, ax + t * vx);
  }

  LatLng _snapToPolyline(LatLng p, List<LatLng> polyline) {
    late LatLng best;
    double bestD = double.infinity;

    for (var i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final proj = _projectOnSegment(p, a, b);
      final d = _meters(proj, p);
      if (d < bestD) {
        bestD = d;
        best = proj;
      }
    }
    return best;
  }

  /* ----------------------------- Live location ----------------------------- */

  Future<void> _startLiveLocation() async {
    // Ask for permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return; // user declined; we just won't show the blue dot
      }
    }

    // Quick seed from last known (fast)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (mounted && last != null) {
        setState(() {
          _me = LatLng(last.latitude, last.longitude);
          _meAccuracy = last.accuracy;
        });
      }
    } catch (_) {}

    // Stream updates
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // meters
    );

    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((
      pos,
    ) {
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _me = here;
        _meAccuracy = pos.accuracy;
      });
      if (_followMe && _mapReady) {
        _map.move(here, _map.camera.zoom);
      }
    }, onError: (_) {});
  }

  Future<void> _centerOnMe() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final here = LatLng(pos.latitude, pos.longitude);
      _safeMove(here, 15);
      setState(() {
        _me = here;
        _meAccuracy = pos.accuracy;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Location unavailable: $e')));
    }
  }

  /* ----------------------------- Search flow ----------------------------- */

  Future<void> _searchByAddress(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _searchedDestination = null;
      _candidateRoutes = [];
      _selectedRoute = null;
      _selectedRoutePoints = [];
      _pickup = null;
      _dropoff = null;
      _osrmSegment = null;
      _editTarget = 'auto';
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
      _searchedDestination = dest;
      _safeMove(dest, 14);

      // Filter routes that pass near the searched destination
      final matches = <DriverRoute>[];
      for (final r in _allRoutes) {
        final pts = _decodeEffectivePolyline(r);
        if (pts.isEmpty) continue;
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

  /* ----------------------------- Interactions ----------------------------- */

  void _selectRoute(DriverRoute r) {
    final pts = _decodeEffectivePolyline(r);

    // If there was a searched destination, offer a default drop-off snapped to route
    LatLng? newDrop =
        _searchedDestination == null
            ? null
            : _snapToPolyline(_searchedDestination!, pts);

    setState(() {
      _selectedRoute = r;
      _selectedRoutePoints = pts;
      _pickup =
          (_pickup != null && pts.length >= 2)
              ? _snapToPolyline(_pickup!, pts)
              : null;
      _dropoff = newDrop;
      _osrmSegment = null;
      _editTarget = 'auto';
    });

    if (pts.isNotEmpty) {
      _safeMove(pts.first, 13);
    }

    _rebuildOsrmIfReady();
  }

  void _onMapTap(TapPosition _, LatLng tap) async {
    if (_selectedRoutePoints.isEmpty) return;

    final snapped = _snapToPolyline(tap, _selectedRoutePoints);

    if (_pickup == null) {
      setState(() {
        _pickup = snapped;
        _editTarget = 'dropoff';
        _osrmSegment = null;
      });
      _rebuildOsrmIfReady();
      return;
    }

    if (_dropoff == null) {
      setState(() {
        _dropoff = snapped;
        _editTarget = 'auto';
        _osrmSegment = null;
      });
      _rebuildOsrmIfReady();
      return;
    }

    // both set
    if (_editTarget == 'pickup') {
      setState(() {
        _pickup = snapped;
        _editTarget = 'dropoff';
        _osrmSegment = null;
      });
      _rebuildOsrmIfReady();
    } else if (_editTarget == 'dropoff') {
      setState(() {
        _dropoff = snapped;
        _editTarget = 'pickup';
        _osrmSegment = null;
      });
      _rebuildOsrmIfReady();
    } else {
      // auto: start a new selection
      setState(() {
        _pickup = snapped;
        _dropoff = null;
        _editTarget = 'dropoff';
        _osrmSegment = null;
      });
      _rebuildOsrmIfReady();
    }
  }

  Future<void> _rebuildOsrmIfReady() async {
    if (_pickup == null || _dropoff == null) return;
    try {
      final seg = await fetchOsrmRoute(start: _pickup!, end: _dropoff!);
      if (!mounted) return;
      setState(() => _osrmSegment = seg);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Routing failed: $e')));
    }
  }

  void _openConfirm() {
    if (_pickup == null || _dropoff == null || _selectedRoute == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ConfirmRidePage(
              pickup: _pickup!,
              destination: _dropoff!,
              routeId: _selectedRoute!.id,
              driverId: _selectedRoute!.driverId,
            ),
      ),
    );
  }

  /* ----------------------------- Build ----------------------------- */

  @override
  Widget build(BuildContext context) {
    final hasDest = _searchedDestination != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(_purple.value),
        centerTitle: true,
        title: const Text(
          'Find a Route & Set Your Trip',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: _SearchBar(
                controller: _destCtrl,
                onSubmit: _searchByAddress,
                onClear: () {
                  setState(() {
                    _searchedDestination = null;
                    _candidateRoutes = [];
                    _selectedRoute = null;
                    _selectedRoutePoints = [];
                    _pickup = null;
                    _dropoff = null;
                    _osrmSegment = null;
                    _error = null;
                    _editTarget = 'auto';
                  });
                },
              ),
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
                        strokeWidth: 3,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ],
                  ),

                // Passenger OSRM segment (pickup → dropoff)
                if (_osrmSegment != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _osrmSegment!.points,
                        strokeWidth: 3,
                        color: _purpleDark,
                      ),
                    ],
                  ),

                // Accuracy ring (NEW)
                if (_me != null && (_meAccuracy ?? 0) > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _me!,
                        radius: (_meAccuracy ?? 0),
                        useRadiusInMeter: true,
                        color: Colors.blue.withOpacity(0.12),
                        borderColor: Colors.blue.withOpacity(0.25),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),

                // Live location blue dot (NEW)
                if (_me != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _me!,
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x55000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Optional: marker for the searched destination (as a hint)
                if (_searchedDestination != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _searchedDestination!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.pin_drop,
                          color: Colors.red,
                          size: 28,
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
                        width: 36,
                        height: 36,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.green,
                          size: 36,
                        ),
                      ),
                    ],
                  ),

                // Dropoff marker
                if (_dropoff != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _dropoff!,
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

          // Quick “center on me” button (NEW)
          Positioned(
            right: 12,
            bottom: 120,
            child: SafeArea(
              child: FloatingActionButton.small(
                heroTag: 'center_me_fab',
                onPressed: _centerOnMe,
                child: const Icon(Icons.my_location),
              ),
            ),
          ),

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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 🔹 Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // 🔹 Step helper text
                    // Row(
                    //   children: [
                    //     const Icon(
                    //       Icons.touch_app,
                    //       size: 18,
                    //       color: Colors.black54,
                    //     ),
                    //     const SizedBox(width: 6),
                    //     Expanded(
                    //       child: Text(
                    //         _searchedDestination == null
                    //             ? 'Type an address to find matching driver routes'
                    //             : _selectedRoute == null
                    //             ? 'Pick a route above'
                    //             : _pickup == null
                    //             ? 'Tap the map to set your PICKUP on the route'
                    //             : _dropoff == null
                    //             ? 'Tap again to set your DROPOFF'
                    //             : _editTarget == 'pickup'
                    //             ? 'Tap the map to adjust your PICKUP'
                    //             : _editTarget == 'dropoff'
                    //             ? 'Tap the map to adjust your DROPOFF'
                    //             : 'Tap the map to start over (new pickup)',
                    //         style: const TextStyle(
                    //           color: Colors.black54,
                    //           fontSize: 13,
                    //           fontWeight: FontWeight.w500,
                    //         ),
                    //       ),
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 14),

                    // 🔹 Status + toggles
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(
                          icon: Icons.flag,
                          label:
                              _searchedDestination == null
                                  ? 'Destination: —'
                                  : 'Destination set',
                        ),
                        GestureDetector(
                          onTap:
                              _selectedRoute == null
                                  ? null
                                  : () =>
                                      setState(() => _editTarget = 'pickup'),
                          child: _Pill(
                            icon: Icons.location_pin,
                            label:
                                _pickup == null
                                    ? 'Pickup: —'
                                    : _editTarget == 'pickup'
                                    ? 'Pickup (editing)'
                                    : 'Pickup set',
                            borderEmphasis: _editTarget == 'pickup',
                          ),
                        ),
                        GestureDetector(
                          onTap:
                              _selectedRoute == null
                                  ? null
                                  : () =>
                                      setState(() => _editTarget = 'dropoff'),
                          child: _Pill(
                            icon: Icons.outbound,
                            label:
                                _dropoff == null
                                    ? 'Dropoff: —'
                                    : _editTarget == 'dropoff'
                                    ? 'Dropoff (editing)'
                                    : 'Dropoff set',
                            borderEmphasis: _editTarget == 'dropoff',
                          ),
                        ),
                        if (_pickup != null || _dropoff != null)
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _pickup = null;
                                _dropoff = null;
                                _osrmSegment = null;
                                _editTarget = 'auto';
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Reset points'),
                          ),

                        // 🔹 Follow me toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Follow me',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Switch(
                              value: _followMe,
                              onChanged: (v) {
                                setState(() => _followMe = v);
                                if (v && _me != null) {
                                  _safeMove(_me!, _map.camera.zoom);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 🔹 CTA button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor:
                              _pickup != null &&
                                      _dropoff != null &&
                                      _selectedRoute != null
                                  ? _purple
                                  : Colors.grey.shade300,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed:
                            (_pickup != null &&
                                    _dropoff != null &&
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

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final void Function(String) onSubmit;
  final VoidCallback onClear;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  static const _purple = Color(0xFF6A27F7);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

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
              controller: widget.controller,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter your destination',
              ),
              onSubmitted: widget.onSubmit,
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close, color: Colors.black45),
              onPressed: () {
                widget.controller.clear();
                widget.onClear();
              },
            ),
          FilledButton(
            onPressed: () => widget.onSubmit(widget.controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
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
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        ), // smaller
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12, // smaller font
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
      selected: selected,
      selectedColor: _purple,
      backgroundColor: Colors.white,
      elevation: selected ? 6 : 1, // tiny lift
      pressElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // modern subtle rounding
        side: BorderSide(
          color: selected ? _purple : Colors.grey.shade300,
          width: 1,
        ),
      ),
      // Glow effect when selected
      avatar:
          selected
              ? Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _purple.withOpacity(0.6),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              )
              : null,
      onSelected: (_) => onTap(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    this.borderEmphasis = false,
  });

  final IconData icon;
  final String label;
  final bool borderEmphasis;

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderEmphasis ? const Color(0xFF6A27F7) : Colors.black12,
          width: borderEmphasis ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
    return const Row(
      children: [
        SizedBox(width: 12),
        Expanded(child: LinearProgressIndicator(minHeight: 6)),
        SizedBox(width: 12),
      ],
    );
  }
}
