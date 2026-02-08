import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:godavao/common/empty_state.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/features/rides/presentation/confirm_ride_page.dart';

/// ---------- Top-level helpers ----------

/// Result of snapping a point onto a polyline, with a monotonic progress value
/// (segmentIndex + t) so we can enforce forward-only movement along the route.
class _SnapResult {
  final LatLng point;

  /// segmentIndex + t (0..poly.length-1). Larger means further along route.
  final double progress;
  const _SnapResult(this.point, this.progress);
}

/// ---------- Models ----------

class DriverRoute {
  final String id;
  final String driverId;
  final String? routeMode; // 'osrm' | 'manual' | null
  final String? name;
  final String? routePolyline;
  final String? manualPolyline;

  DriverRoute.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      driverId = m['driver_id'] as String,
      routeMode = (m['route_mode'] as String?),
      name = (m['name'] as String?),
      routePolyline = (m['route_polyline'] as String?),
      manualPolyline = (m['manual_polyline'] as String?);
}

/// ---------- Page ----------

class PassengerMapPage extends StatefulWidget {
  const PassengerMapPage({super.key});

  @override
  State<PassengerMapPage> createState() => _PassengerMapPageState();
}

class _PassengerMapPageState extends State<PassengerMapPage> {
  // Services & helpers
  final SupabaseClient _sb = Supabase.instance.client;
  final MapController _map = MapController();
  final PolylinePoints _polyDecoder = PolylinePoints();
  final Distance _distance = const Distance();

  // UI palette
  static const _purple = Color(0xFF5A20D7); // Darker for better contrast
  static const _purpleDark = Color(0xFF3B10A7);

  // Map readiness
  bool _mapReady = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;

  // Search controllers
  final _pickupCtrl = TextEditingController();
  final _destCtrl = TextEditingController();

  // Data
  bool _loading = false;
  String? _error;

  LatLng? _searchedPickup;
  LatLng? _searchedDestination;

  List<DriverRoute> _allRoutes = [];
  List<DriverRoute> _candidateRoutes = [];
  DriverRoute? _selectedRoute;
  List<LatLng> _selectedRoutePoints = [];

  // Passenger-chosen points (snapped to selected route)
  _SnapResult? _pickup; // snapped point + progress
  _SnapResult? _dropoff; // snapped point + progress

  // Computed OSRM segment from pickup → dropoff
  Polyline? _osrmSegment;

  // Which point the next tap edits
  String _editTarget = 'auto'; // 'pickup' | 'dropoff' | 'auto'

  // Config
  static const double _matchRadiusMeters = 600;
  static const double _progressEps = 1e-6; // tiny epsilon for comparisons

  // Live user location
  StreamSubscription<Position>? _posSub;
  LatLng? _me;
  double? _meAccuracy; // meters
  final bool _followMe = false;

  // Filtering
  bool _showAllRoutes = false;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
    _startLiveLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _pickupCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  /* ===================== Data Loading ===================== */

  Future<void> _loadRoutes() async {
    try {
      final data = await _sb
          .from('driver_routes')
          .select(
            'id, driver_id, name, route_mode, route_polyline, manual_polyline, is_locked, capacity_available, is_active',
          )
          .eq('is_active', true)
          .eq('is_locked', false)
          .gt('capacity_available', 0);

      _allRoutes =
          (data as List)
              .map((m) => DriverRoute.fromMap(m as Map<String, dynamic>))
              .toList();

      // Initial candidate set
      await _refreshCandidates();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load routes: $e');
    }
  }

  /* ===================== Map Helpers ===================== */

  void _safeMove(LatLng center, double zoom) {
    if (!_mapReady) {
      _pendingCenter = center;
      _pendingZoom = zoom;
      return;
    }
    _map.move(center, zoom);
  }

  // Pick the effective encoded polyline: prefer the mode’s polyline, fallback to the other.
  List<LatLng> _decodeEffectivePolyline(DriverRoute r) {
    String? encoded;
    if (r.routeMode == 'manual') {
      encoded = r.manualPolyline ?? r.routePolyline;
    } else if (r.routeMode == 'osrm') {
      encoded = r.routePolyline ?? r.manualPolyline;
    } else {
      encoded = r.routePolyline ?? r.manualPolyline;
    }
    if (encoded == null || encoded.isEmpty) return const [];

    final pts = _polyDecoder.decodePolyline(encoded);
    return pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }

  double _meters(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

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

  _SnapResult _snapWithProgress(LatLng p, List<LatLng> poly) {
    // Find closest projection & compute progress = segIndex + t (0..n-1)
    double bestD = double.infinity;
    LatLng bestPoint = poly.first;
    double bestProgress = 0.0;

    for (var i = 0; i < poly.length - 1; i++) {
      final a = poly[i];
      final b = poly[i + 1];

      // project
      final ax = a.longitude, ay = a.latitude;
      final bx = b.longitude, by = b.latitude;
      final px = p.longitude, py = p.latitude;

      final vx = bx - ax, vy = by - ay;
      final wx = px - ax, wy = py - ay;

      final c1 = vx * wx + vy * wy;
      final c2 = vx * vx + vy * vy;

      double t;
      if (c2 == 0) {
        t = 0.0;
      } else if (c1 <= 0) {
        t = 0.0;
      } else if (c2 <= c1) {
        t = 1.0;
      } else {
        t = c1 / c2;
      }

      final proj = LatLng(ay + t * vy, ax + t * vx);
      final d = _meters(proj, p);
      if (d < bestD) {
        bestD = d;
        bestPoint = proj;
        bestProgress = i + t;
      }
    }
    return _SnapResult(bestPoint, bestProgress);
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

  _SnapResult? _safeSnap(LatLng? p, List<LatLng> poly) {
    if (p == null || poly.length < 2) return null;
    return _snapWithProgress(p, poly);
  }

  /* ===================== Live Location ===================== */

  Future<void> _startLiveLocation() async {
    // Permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return; // user declined; skip blue dot
      }
    }

    // Seed from last known (fast)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (mounted && last != null) {
        setState(() {
          _me = LatLng(last.latitude, last.longitude);
          _meAccuracy = last.accuracy;
        });
      }
    } catch (_) {}

    // Subscribe
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
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
      if (mounted) {
        setState(() {
          _me = here;
          _meAccuracy = pos.accuracy;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Location unavailable: $e')));
    }
  }

  /* ===================== Search & Filtering ===================== */

  Future<void> _searchPickupAddress(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await locationFromAddress(text);
      if (results.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Pickup not found. Try a more specific address.';
        });
        return;
      }
      final pick = LatLng(results.first.latitude, results.first.longitude);
      _searchedPickup = pick;
      _safeMove(pick, 14);
      await _refreshCandidates();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Pickup search failed: $e';
      });
    }
  }

  Future<void> _searchByAddress(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _searchedDestination = null;
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

      await _refreshCandidates();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Future<void> _refreshCandidates() async {
    // When “Show all routes” is on, we bypass filtering.
    if (_showAllRoutes) {
      _candidateRoutes = List.of(_allRoutes);
      if (mounted) setState(() {});
      return;
    }

    // Otherwise filter by proximity to pickup and/or destination.
    final matches = <DriverRoute>[];
    for (final r in _allRoutes) {
      final pts = _decodeEffectivePolyline(r);
      if (pts.isEmpty) continue;

      bool okPickup = true;
      bool okDest = true;

      if (_searchedPickup != null) {
        okPickup = _isPointNearPolyline(
          _searchedPickup!,
          pts,
          _matchRadiusMeters,
        );
      }
      if (_searchedDestination != null) {
        okDest = _isPointNearPolyline(
          _searchedDestination!,
          pts,
          _matchRadiusMeters,
        );
      }

      // Rules:
      // - If both set: route must be near BOTH.
      // - If only one set: route must be near that one.
      // - If none set: show all.
      final noneSet = _searchedPickup == null && _searchedDestination == null;
      if (noneSet || (okPickup && okDest)) {
        matches.add(r);
      }
    }

    _candidateRoutes = matches;
    if (mounted) setState(() {});
  }

  /* ===================== Interactions ===================== */

  void _selectRoute(DriverRoute r) {
    final pts = _decodeEffectivePolyline(r);

    // Use searched pickup/destination to suggest initial snapped points
    final sp =
        _safeSnap(_searchedPickup, pts) ?? _safeSnap(_pickup?.point, pts);
    final sd =
        _safeSnap(_searchedDestination, pts) ?? _safeSnap(_dropoff?.point, pts);

    _SnapResult? picked;
    _SnapResult? dropped;

    // Enforce forward order when both are available
    if (sp != null && sd != null) {
      if (sp.progress + _progressEps < sd.progress) {
        picked = sp;
        dropped = sd;
      } else {
        // If destination is before pickup, choose pickup only; user will set dropoff later.
        picked = sp;
        dropped = null;
        _showToast('Pick a drop-off further along the route.');
      }
    } else {
      picked = sp;
      dropped = sd;
    }

    setState(() {
      _selectedRoute = r;
      _selectedRoutePoints = pts;
      _pickup = picked;
      _dropoff = dropped;
      _osrmSegment = null;
      _editTarget = 'auto';
    });

    if (pts.isNotEmpty) _safeMove(pts.first, 13);
    _rebuildOsrmIfReady();
  }

  void _onMapTap(TapPosition _, LatLng tap) {
    if (_selectedRoutePoints.isEmpty) return;

    final snapped = _snapWithProgress(tap, _selectedRoutePoints);

    setState(() {
      // Determine which endpoint we’re editing
      if (_pickup == null) {
        _pickup = snapped;
        _dropoff = null;
        _editTarget = 'dropoff';
      } else if (_dropoff == null) {
        // Enforce forward-only: dropoff must be AFTER pickup
        if (snapped.progress > _pickup!.progress + _progressEps) {
          _dropoff = snapped;
          _editTarget = 'auto';
        } else {
          _showToast('Drop-off must be after pickup along the route.');
        }
      } else if (_editTarget == 'pickup') {
        // Ensure pickup stays BEFORE dropoff
        if (snapped.progress + _progressEps < _dropoff!.progress) {
          _pickup = snapped;
          _editTarget = 'dropoff';
        } else {
          _showToast('Pickup must be before the drop-off.');
        }
      } else if (_editTarget == 'dropoff') {
        // Ensure dropoff stays AFTER pickup
        if (snapped.progress > _pickup!.progress + _progressEps) {
          _dropoff = snapped;
          _editTarget = 'pickup';
        } else {
          _showToast('Drop-off must be after the pickup.');
        }
      } else {
        // auto: reset with new pickup, force user to pick a later dropoff
        _pickup = snapped;
        _dropoff = null;
        _editTarget = 'dropoff';
      }
      _osrmSegment = null;
    });

    _rebuildOsrmIfReady();
  }

  Future<void> _rebuildOsrmIfReady() async {
    if (_pickup == null || _dropoff == null) return;

    // Final guard for forward-only (should already be enforced)
    if (!(_pickup!.progress + _progressEps < _dropoff!.progress)) {
      _showToast('Drop-off must be after pickup along the route.');
      return;
    }

    try {
      final seg = await fetchOsrmRoute(
        start: _pickup!.point,
        end: _dropoff!.point,
      );
      if (!mounted) return;
      setState(() => _osrmSegment = seg);
    } catch (e) {
      if (!mounted) return;
      _showToast('Routing failed: $e');
    }
  }

  void _openConfirm() {
    if (_pickup == null || _dropoff == null || _selectedRoute == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => ConfirmRidePage(
              pickup: _pickup!.point,
              destination: _dropoff!.point,
              routeId: _selectedRoute!.id,
              driverId: _selectedRoute!.driverId,
            ),
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /* ===================== Build ===================== */

  @override
  Widget build(BuildContext context) {
    final hasAnySearch =
        _searchedPickup != null || _searchedDestination != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withValues(alpha: 0.4), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        backgroundColor: const Color.fromARGB(3, 0, 0, 0),
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: _purple,
                size: 18,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: const Text(
          'Find a Route',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(160),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: _SearchBar(
                    hintText: 'Enter pickup (optional)',
                    controller: _pickupCtrl,
                    onSubmit: _searchPickupAddress,
                    onClear: () {
                      setState(() {
                        _pickupCtrl.clear();
                        _searchedPickup = null;
                      });
                      _refreshCandidates();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: _SearchBar(
                    hintText: 'Enter destination',
                    controller: _destCtrl,
                    onSubmit: _searchByAddress,
                    onClear: () {
                      setState(() {
                        _destCtrl.clear();
                        _searchedDestination = null;
                        _selectedRoute = null;
                        _selectedRoutePoints = [];
                        _pickup = null;
                        _dropoff = null;
                        _osrmSegment = null;
                        _editTarget = 'auto';
                        _error = null;
                      });
                      _refreshCandidates();
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Switch.adaptive(
                      value: _showAllRoutes,
                      onChanged: (v) async {
                        setState(() => _showAllRoutes = v);
                        await _refreshCandidates();
                      },
                      activeTrackColor: _purple,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _showAllRoutes
                            ? 'Showing all active routes'
                            : 'Filter routes by proximity to pickup/destination',
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(7.19, 125.45),
                initialZoom: 12.5,
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
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.godavao.app',
                ),

                // Driver route
                if (_selectedRoutePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _selectedRoutePoints,
                        strokeWidth: 3,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ],
                  ),

                // OSRM segment pickup → dropoff
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

                // Accuracy ring
                if (_me != null && (_meAccuracy ?? 0) > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _me!,
                        radius: (_meAccuracy ?? 0),
                        useRadiusInMeter: true,
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderColor: Colors.blue.withValues(alpha: 0.25),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),

                // Blue dot
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

                // Searched pickup/destination hints
                if (_searchedPickup != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _searchedPickup!,
                        width: 30,
                        height: 30,
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.green,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
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

                // Pickup (snapped to selected route)
                if (_pickup != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickup!.point,
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

                // Dropoff (snapped)
                if (_dropoff != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _dropoff!.point,
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

          // Route carousel when any search is set
          if (hasAnySearch)
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
                            onRetry: () async {
                              if (_destCtrl.text.isNotEmpty) {
                                await _searchByAddress(_destCtrl.text);
                              } else if (_pickupCtrl.text.isNotEmpty) {
                                await _searchPickupAddress(_pickupCtrl.text);
                              } else {
                                await _refreshCandidates();
                              }
                            },
                          )
                          : _candidateRoutes.isEmpty
                          ? _EmptyRoutesBar(
                            message:
                                _showAllRoutes
                                    ? 'No active routes found.'
                                    : 'No routes near your pickup/destination.',
                            onRetry: () async {
                              await _refreshCandidates();
                            },
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
                              final label =
                                  (r.name != null && r.name!.trim().isNotEmpty)
                                      ? r.name!
                                      : 'Route ${i + 1}';
                              return _RouteChip(
                                label: label,
                                selected: sel,
                                onTap: () => _selectRoute(r),
                              );
                            },
                          ),
                ),
              ),
            ),

          // Bottom controls
          BottomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedRoute != null) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(
                          icon: Icons.person_pin_circle,
                          label:
                              _searchedPickup == null
                                  ? 'Pickup filter'
                                  : 'Pickup ✓',
                        ),
                        _Pill(
                          icon: Icons.flag,
                          label:
                              _searchedDestination == null
                                  ? 'Destination'
                                  : 'Destination ✓',
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _editTarget = 'pickup'),
                          child: _Pill(
                            icon: Icons.location_pin,
                            label: _pickup == null ? 'Pickup' : 'Pickup ✓',
                            borderEmphasis: _editTarget == 'pickup',
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _editTarget = 'dropoff'),
                          child: _Pill(
                            icon: Icons.outbound,
                            label: _dropoff == null ? 'Dropoff' : 'Dropoff ✓',
                            borderEmphasis: _editTarget == 'dropoff',
                          ),
                        ),
                        FloatingActionButton.small(
                          heroTag: 'center_me_fab',
                          onPressed: _centerOnMe,
                          backgroundColor: _purple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          child: const Icon(Icons.my_location, size: 20),
                        ),
                        if (_pickup != null || _dropoff != null)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _pickup = null;
                                _dropoff = null;
                                _osrmSegment = null;
                                _editTarget = 'auto';
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(
                              Icons.refresh,
                              size: 18,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (_pickup != null && _dropoff != null)
                                ? _purple
                                : Colors.grey.shade300,
                        disabledBackgroundColor: Colors.grey.shade300,
                        foregroundColor:
                            (_pickup != null && _dropoff != null)
                                ? Colors.white
                                : Colors.black54,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed:
                          (_pickup != null && _dropoff != null)
                              ? _openConfirm
                              : null,
                      child: const Text(
                        'Review Fare',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ===================== Small UI Widgets ===================== */

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    this.hintText = 'Search',
  });

  final TextEditingController controller;
  final void Function(String) onSubmit;
  final VoidCallback onClear;
  final String hintText;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
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
            color: Colors.black.withValues(alpha: 0.06),
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
              textAlignVertical: TextAlignVertical.top,
              controller: widget.controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hintText,
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

  static const _purple = Color(0xFF5A20D7); // Darker for better contrast

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
      selected: selected,
      selectedColor: _purple,
      backgroundColor: Colors.white,
      elevation: selected ? 6 : 1,
      pressElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? _purple : Colors.grey.shade300,
          width: 1,
        ),
      ),
      checkmarkColor: Colors.white,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderEmphasis ? const Color(0xFF5A20D7) : Colors.black26,
          width: borderEmphasis ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black87),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: EmptyStateCard(
        icon: Icons.route_outlined,
        title: message,
        subtitle: 'Try refreshing or adjusting your pickup/destination.',
        compact: true,
        showSubtitle: false,
        ctaLabel: 'Retry',
        onCta: onRetry,
      ),
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

class BottomCard extends StatelessWidget {
  final Widget child;
  const BottomCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
