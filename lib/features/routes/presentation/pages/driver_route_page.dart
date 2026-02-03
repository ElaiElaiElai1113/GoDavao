import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;
import 'package:geolocator/geolocator.dart';

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/core/fare_service.dart';
import 'package:godavao/main.dart' show localNotify;

import 'package:godavao/features/routes/presentation/pages/vehicle_switcher.dart';
import 'package:godavao/features/auth/presentation/vehicle_form.dart';

enum RouteMode { osrm, manual }

class DriverRoutePage extends StatefulWidget {
  const DriverRoutePage({super.key});
  @override
  State<DriverRoutePage> createState() => _DriverRoutePageState();
}

class _DriverRoutePageState extends State<DriverRoutePage> {
  final MapController _map = MapController();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Fare + fees
  final FareService _fareService = FareService();
  static const double _platformFeePct = 0.15;

  // Mode
  RouteMode _mode = RouteMode.osrm;

  // OSRM mode
  LatLng? _start;
  LatLng? _end;
  Polyline? _osrmRoute;
  double? _osrmKm;
  double? _osrmMins;

  // Manual mode
  final List<LatLng> _manualPoints = [];
  Polyline? _manualRoute;
  double? _manualKm;

  // Vehicle
  String? _vehicleId;
  int? _vehicleSeats;

  // UI state
  bool _publishing = false;
  bool _checkingVehicles = true;
  bool _hasAnyVehicle = false;
  String? _error;

  // Location
  LatLng? _myPos;
  StreamSubscription<Position>? _posSub;
  bool _followMe = false;
  bool _locPermDenied = false;
  bool _locating = false;

  // Theme tokens
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkHasVehicles();
    _initLocation();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _posSub?.cancel();
    super.dispose();
  }

  // ---------- helpers ----------

  InputDecoration _decor({String? label, String? hint}) =>
      const InputDecoration(border: UnderlineInputBorder()).copyWith(
        labelText: label,
        hintText: hint,
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: _purple, width: 2),
        ),
      );

  Future<void> _checkHasVehicles() async {
    setState(() {
      _checkingVehicles = true;
      _error = null;
    });
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        _hasAnyVehicle = false;
      } else {
        final res = await _sb
            .from('vehicles')
            .select('id')
            .eq('driver_id', uid)
            .limit(1);
        _hasAnyVehicle = (res as List).isNotEmpty;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _checkingVehicles = false);
    }
  }

  double _pathKm(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    final d = Distance();
    double sum = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      sum += d.as(LengthUnit.Kilometer, pts[i], pts[i + 1]);
    }
    return sum;
  }

  // ---------- LOCATION ----------

  Future<void> _initLocation() async {
    setState(() {
      _locating = true;
      _locPermDenied = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locating = false);
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _locPermDenied = true;
        });
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _updateMyPos(last);
      } else {
        final current = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 8),
        );
        _updateMyPos(current);
      }

      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(_updateMyPos);
    } catch (_) {
      // silent; user can still make routes
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _updateMyPos(Position pos) {
    final p = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() => _myPos = p);
    if (_followMe) _map.move(p, _map.camera.zoom);
  }

  void _toggleFollow() {
    setState(() => _followMe = !_followMe);
    if (_followMe && _myPos != null) {
      _map.move(_myPos!, math.max(_map.camera.zoom, 15));
    }
  }

  void _centerOnMe() {
    if (_myPos == null) return;
    _map.move(_myPos!, math.max(_map.camera.zoom, 15));
  }

  // ---------- fare ----------

  FareBreakdown? _fare;
  double? _driverNet;

  void _clearFare() {
    setState(() {
      _fare = null;
      _driverNet = null;
    });
  }

  Future<void> _recomputeFareEstimate() async {
    try {
      final seats = (_vehicleSeats ?? 1).clamp(1, 99);

      if (_mode == RouteMode.osrm) {
        if (_start == null || _end == null) {
          _clearFare();
          return;
        }

        final f = await _fareService.estimate(
          pickup: _start!,
          destination: _end!,
          seats: seats,
          platformFeeRate: _platformFeePct, // 0.15
          surgeMultiplier: 1.0,
        );

        if (!mounted) return;
        setState(() {
          _fare = f;
          _driverNet = f.driverTake;
        });
      } else {
        if (_manualPoints.length < 2) {
          _clearFare();
          return;
        }

        final km = _manualKm ?? _pathKm(_manualPoints);
        const avgKmh = 22.0;
        final mins = math.max((km / avgKmh) * 60.0, 1.0);

        final f = _fareService.estimateForDistance(
          distanceKm: km,
          durationMin: mins,
          seats: seats,
          platformFeeRate: _platformFeePct,
          surgeMultiplier: 1.0,
        );

        if (!mounted) return;
        setState(() {
          _fare = f;
          _driverNet = f.driverTake;
        });
      }
    } catch (_) {
      _clearFare();
    }
  }

  // Build breakdown rows from FareBreakdown
  List<Widget> _fareBreakdownLines() {
    if (_fare == null) return [];
    final f = _fare!;

    String seatsLabel() {
      if (f.seatsBilled <= 1) return '1';
      final disc = (f.carpoolDiscountPct * 100).toStringAsFixed(0);
      return '${f.seatsBilled} (disc $disc%)';
    }

    return [
      _StatRow(
        icon: Icons.flag,
        label: 'Base + Distance + Time',
        value: '₱${f.subtotal.toStringAsFixed(0)}',
      ),
      if (f.nightSurcharge > 0)
        _StatRow(
          icon: Icons.nightlight_round,
          label: 'Night Surcharge',
          value: '₱${f.nightSurcharge.toStringAsFixed(0)}',
        ),
      if (f.surgeMultiplier != 1.0)
        _StatRow(
          icon: Icons.trending_up,
          label: 'Surge Multiplier',
          value: '×${f.surgeMultiplier.toStringAsFixed(2)}',
        ),
      _StatRow(
        icon: Icons.event_seat,
        label: 'Seats Billed',
        value: seatsLabel(),
      ),
      const Divider(height: 18),
      _StatRow(
        icon: Icons.attach_money,
        label: 'Passenger Total',
        value: '₱${f.total.toStringAsFixed(0)}',
      ),
      _StatRow(
        icon: Icons.receipt_long,
        label: 'Platform Fee',
        value: '₱${f.platformFee.toStringAsFixed(0)}',
      ),
      _StatRow(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Driver Net',
        value: '₱${f.driverTake.toStringAsFixed(0)}',
      ),
    ];
  }

  // ---------- map interactions ----------

  void _onMapTap(TapPosition _, LatLng p) async {
    if (_mode == RouteMode.manual) {
      setState(() {
        _manualPoints.add(p);
        _manualKm = _pathKm(_manualPoints);
        _manualRoute = Polyline(
          points: List.of(_manualPoints),
          strokeWidth: 4,
          color: _purpleDark.withValues(alpha: .9),
        );
      });
      await _recomputeFareEstimate();
    }
  }

  void _onMapLongPress(TapPosition _, LatLng p) async {
    if (_mode == RouteMode.osrm) {
      if (_start == null) {
        setState(() {
          _start = p;
          _end = null;
          _osrmRoute = null;
          _osrmKm = null;
          _osrmMins = null;
          _error = null;
        });
        _clearFare();
        return;
      }
      if (_end == null) {
        setState(() => _end = p);
        try {
          final poly = await fetchOsrmRoute(start: _start!, end: _end!);
          setState(() => _osrmRoute = poly);
          try {
            final d = await fetchOsrmRouteDetailed(start: _start!, end: _end!);
            setState(() {
              _osrmKm = d.distanceMeters / 1000.0;
              _osrmMins = d.durationSeconds / 60.0;
            });
          } catch (_) {}
          await _recomputeFareEstimate();
        } catch (e) {
          setState(() => _error = 'Routing failed: $e');
          _clearFare();
        }
        return;
      }
      // third long-press: new start
      setState(() {
        _start = p;
        _end = null;
        _osrmRoute = null;
        _osrmKm = null;
        _osrmMins = null;
        _error = null;
      });
      _clearFare();
    } else {
      showModalBottomSheet<void>(
        context: context,
        builder:
            (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                      onPressed: () async {
                        Navigator.pop(context);
                        if (_manualPoints.isNotEmpty) {
                          setState(() {
                            _manualPoints.removeLast();
                            _manualKm = _pathKm(_manualPoints);
                            _manualRoute =
                                _manualPoints.length >= 2
                                    ? Polyline(
                                      points: List.of(_manualPoints),
                                      strokeWidth: 4,
                                      color: _purpleDark.withValues(alpha: .9),
                                    )
                                    : null;
                          });
                          await _recomputeFareEstimate();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                      onPressed: () async {
                        Navigator.pop(context);
                        setState(() {
                          _manualPoints.clear();
                          _manualKm = 0;
                          _manualRoute = null;
                        });
                        await _recomputeFareEstimate();
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: _purple),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(foregroundColor: _purple),
                    ),
                  ],
                ),
              ),
            ),
      );
    }
  }

  // ---------- publish ----------

  Future<void> _publish() async {
    if (_vehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a vehicle first.')),
      );
      return;
    }

    if (_mode == RouteMode.osrm) {
      if (_start == null || _end == null || _osrmRoute == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Long-press to set START and DESTINATION.'),
          ),
        );
        return;
      }
    } else {
      if (_manualPoints.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap at least two points on the map.')),
        );
        return;
      }
    }

    setState(() => _publishing = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) throw 'Not signed in';

      final seats = _vehicleSeats ?? 1;

      String? routePolyline;
      String? manualPolyline;
      double? startLat;
      double? startLng;
      double? endLat;
      double? endLng;

      if (_mode == RouteMode.osrm) {
        final coords =
            _osrmRoute!.points.map((p) => [p.latitude, p.longitude]).toList();
        routePolyline = gpa.encodePolyline(coords);
        startLat = _start!.latitude;
        startLng = _start!.longitude;
        endLat = _end!.latitude;
        endLng = _end!.longitude;
      } else {
        final coords =
            _manualPoints.map((p) => [p.latitude, p.longitude]).toList();
        manualPolyline = gpa.encodePolyline(coords);
        startLat = _manualPoints.first.latitude;
        startLng = _manualPoints.first.longitude;
        endLat = _manualPoints.last.latitude;
        endLng = _manualPoints.last.longitude;
      }

      await _sb.from('driver_routes').insert({
        'driver_id': user.id,
        'vehicle_id': _vehicleId,
        'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'route_mode': _mode == RouteMode.osrm ? 'osrm' : 'manual',
        'route_polyline': routePolyline,
        'manual_polyline': manualPolyline,
        'start_lat': startLat,
        'start_lng': startLng,
        'end_lat': endLat,
        'end_lng': endLng,
        'capacity_total': seats,
        'capacity_available': seats,
        'is_active': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Route published!')));
      }

      await localNotify.show(
        0,
        'Route Published',
        'Your driver route has been published.',
        const NotificationDetails(
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

      if (!mounted) return;
      setState(() {
        _nameCtrl.clear();
        _notesCtrl.clear();

        _start = null;
        _end = null;
        _osrmRoute = null;
        _osrmKm = null;
        _osrmMins = null;

        _manualPoints.clear();
        _manualRoute = null;
        _manualKm = null;

        _fare = null;
        _driverNet = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Publish failed: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  // ---------- UI ----------

  String _fareLine() {
    if (_fare == null) return '—';
    final dist = _fare!.distanceKm.toStringAsFixed(1);
    final time =
        _mode == RouteMode.osrm && _osrmMins != null
            ? ', ${_fare!.durationMin.toStringAsFixed(0)} min'
            : '';
    return '₱${_fare!.total.toStringAsFixed(0)} ($dist km$time)';
    // note: total is passenger's pay; breakdown shows fee + driver take
  }

  String _driverNetLine() {
    if (_driverNet == null) return '—';
    final pct = (_platformFeePct * 100).toStringAsFixed(0);
    return '₱${_driverNet!.toStringAsFixed(0)} (after $pct% fee)';
  }

  @override
  Widget build(BuildContext context) {
    final center = _myPos ?? _start ?? const LatLng(7.1907, 125.4553);

    return Scaffold(
      backgroundColor: _bg,
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
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ),
        title: const Text(
          'Create Driver Route',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: _PublishFab(
        enabled:
            !_publishing &&
            ((_mode == RouteMode.osrm &&
                    _start != null &&
                    _end != null &&
                    _osrmRoute != null) ||
                (_mode == RouteMode.manual && _manualPoints.length >= 2)) &&
            _vehicleId != null,
        busy: _publishing,
        onPressed: _publish,
      ),
      body: Stack(
        children: [
          // MAP
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
                onTap: _onMapTap,
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourcompany.godavao',
                ),

                if (_myPos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _myPos!,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _purple.withValues(alpha: .15),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: _purple,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                if (_mode == RouteMode.osrm && _osrmRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _osrmRoute!.points,
                        strokeWidth: 4,
                        color: _purpleDark.withValues(alpha: .9),
                      ),
                    ],
                  ),

                if (_mode == RouteMode.manual && _manualRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _manualRoute!.points,
                        strokeWidth: 4,
                        color: _purpleDark.withValues(alpha: .9),
                      ),
                    ],
                  ),

                if (_mode == RouteMode.osrm && _start != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _start!,
                        width: 32,
                        height: 32,
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.green,
                          size: 30,
                        ),
                      ),
                    ],
                  ),

                if (_mode == RouteMode.osrm && _end != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _end!,
                        width: 32,
                        height: 32,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                    ],
                  ),

                if (_mode == RouteMode.manual && _manualPoints.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _manualPoints.first,
                        width: 28,
                        height: 28,
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.green,
                          size: 26,
                        ),
                      ),
                      if (_manualPoints.length > 1)
                        Marker(
                          point: _manualPoints.last,
                          width: 28,
                          height: 28,
                          child: const Icon(
                            Icons.flag,
                            color: Colors.red,
                            size: 26,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),

          // Top-right map controls
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- Center on Me Button ---
                    _GlassFab(
                      heroTag: 'centerOnMe',
                      icon: Icons.my_location,
                      tooltip:
                          _myPos == null
                              ? (_locPermDenied
                                  ? 'Location permission denied'
                                  : _locating
                                  ? 'Locating…'
                                  : 'Location unavailable')
                              : 'Center on me',
                      onPressed: _myPos == null ? null : _centerOnMe,
                      active: false,
                    ),
                    const SizedBox(height: 10),

                    // --- Follow Me Button ---
                    _GlassFab(
                      heroTag: 'followMe',
                      icon: Icons.navigation_rounded,
                      tooltip: _followMe ? 'Disable follow' : 'Enable follow',
                      onPressed: _myPos == null ? null : _toggleFollow,
                      active: _followMe,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Mode chip + hint (map overlay)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 8, right: 100),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ModeSegment(
                    mode: _mode,
                    onChanged: (m) async {
                      setState(() {
                        _mode = m;
                        _error = null;
                      });
                      await _recomputeFareEstimate();
                    },
                  ),
                  _HintPill(
                    text:
                        _mode == RouteMode.osrm
                            ? (_start == null
                                ? 'Long-press map to set START'
                                : _end == null
                                ? 'Long-press to set DESTINATION'
                                : 'Long-press again to reset START')
                            : 'Tap to add points · Long-press for Undo/Clear',
                  ),
                ],
              ),
            ),
          ),

          // Always-visible quick stats
          const SizedBox(height: 25),
          if (_fare != null || _driverNet != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_fare != null)
                        _InfoChip(
                          icon: Icons.local_taxi,
                          text: 'Estimated Fare: ${_fareLine()}',
                        ),
                      if (_driverNet != null)
                        _InfoChip(
                          icon: Icons.account_balance_wallet_outlined,
                          text: 'Driver Net: ${_driverNetLine()}',
                        ),
                    ],
                  ),
                ),
              ),
            ),

          if (_error != null)
            Positioned(
              top: 48,
              left: 8,
              right: 8,
              child: Material(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),

          // COLLAPSIBLE SHEET
          _CollapsibleRouteSheet(
            checkingVehicles: _checkingVehicles,
            hasAnyVehicle: _hasAnyVehicle,
            vehicleSeats: _vehicleSeats,
            onAddVehicle: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const VehicleForm()),
              );
              await _checkHasVehicles();
            },
            onVehicleChanged: (v) async {
              setState(() {
                _vehicleId = v['id'] as String?;
                _vehicleSeats = (v['seats'] as int?) ?? 0;
              });
              await _recomputeFareEstimate();
            },
            osrmInfo:
                (_mode == RouteMode.osrm && _osrmRoute != null)
                    ? '${_osrmKm == null ? '—' : _osrmKm!.toStringAsFixed(1)} km • '
                        '${_osrmMins == null ? '—' : _osrmMins!.toStringAsFixed(0)} min'
                    : null,
            manualInfo:
                (_mode == RouteMode.manual && _manualRoute != null)
                    ? '${_manualKm?.toStringAsFixed(1) ?? '—'} km (manual)'
                    : null,
            fareText: _fareLine(),
            netText: _driverNetLine(),
            nameCtrl: _nameCtrl,
            notesCtrl: _notesCtrl,

            // NEW: full breakdown widgets
            fareBreakdown: _fareBreakdownLines(),
          ),
        ],
      ),
    );
  }
}

/* ---------- UI pieces ---------- */

class _PublishFab extends StatelessWidget {
  const _PublishFab({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .6,
      child: FloatingActionButton.extended(
        onPressed: enabled ? onPressed : null,
        icon:
            busy
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.publish),
        label: Text(busy ? 'Publishing…' : 'Publish Route'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({required this.mode, required this.onChanged});

  final RouteMode mode;
  final ValueChanged<RouteMode> onChanged;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        backgroundBlendMode: BlendMode.overlay,
      ),
      child: Row(
        children:
            RouteMode.values.map((rm) {
              final selected = rm == mode;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 42,
                  decoration: BoxDecoration(
                    gradient:
                        selected
                            ? const LinearGradient(
                              colors: [_purple, _purpleDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                            : LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.8),
                                Colors.white.withValues(alpha: 0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    borderRadius: BorderRadius.circular(40),
                    boxShadow:
                        selected
                            ? [
                              BoxShadow(
                                color: _purple.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ]
                            : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    border: Border.all(
                      color:
                          selected
                              ? Colors.transparent
                              : _purple.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: () => onChanged(rm),
                    child: Center(
                      child: Text(
                        rm == RouteMode.osrm ? "OSRM" : "Manual",
                        style: TextStyle(
                          color: selected ? Colors.white : _purpleDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.3,
                          shadows:
                              selected
                                  ? [
                                    const Shadow(
                                      color: Colors.black26,
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                  : [],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 14, color: Colors.black54),
          SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _CollapsibleRouteSheet extends StatelessWidget {
  const _CollapsibleRouteSheet({
    required this.checkingVehicles,
    required this.hasAnyVehicle,
    required this.vehicleSeats,
    required this.onAddVehicle,
    required this.onVehicleChanged,
    required this.osrmInfo,
    required this.manualInfo,
    required this.fareText,
    required this.netText,
    required this.nameCtrl,
    required this.notesCtrl,
    this.fareBreakdown, // NEW
  });

  final bool checkingVehicles;
  final bool hasAnyVehicle;
  final int? vehicleSeats;
  final VoidCallback onAddVehicle;
  final ValueChanged<Map<String, dynamic>> onVehicleChanged;

  final String? osrmInfo;
  final String? manualInfo;
  final String fareText;
  final String netText;

  final TextEditingController nameCtrl;
  final TextEditingController notesCtrl;

  final List<Widget>? fareBreakdown; // NEW

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      minChildSize: .18,
      maxChildSize: .88,
      initialChildSize: .22,
      snap: true,
      snapSizes: const [.18, .42, .88],
      builder: (ctx, scroll) {
        return Material(
          elevation: 16,
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetHandle(),
                      const SizedBox(height: 10),

                      // quick stats (collapsed view)
                      Row(
                        children: [
                          Expanded(
                            child: _StatRow(
                              icon: Icons.local_taxi,
                              label: 'Estimated Fare',
                              value: fareText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatRow(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Driver Net',
                              value: netText,
                            ),
                          ),
                        ],
                      ),
                      if (osrmInfo != null || manualInfo != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.route,
                              size: 16,
                              color: Colors.black54,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              osrmInfo ?? manualInfo!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],

                      // NEW: Fare breakdown
                      if (fareBreakdown != null &&
                          fareBreakdown!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Text(
                          'Fare Breakdown',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Column(children: fareBreakdown!),
                      ],

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      Text(
                        'Vehicle',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),

                      if (checkingVehicles)
                        const SizedBox(
                          height: 36,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (!hasAnyVehicle)
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'No vehicles yet. Add one to publish routes.',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Vehicle'),
                              onPressed: onAddVehicle,
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            VehicleSwitcher(onChanged: onVehicleChanged),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Seats'),
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(
                                    vehicleSeats == null
                                        ? '—'
                                        : '$vehicleSeats seats',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Route name (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassFab extends StatelessWidget {
  final String heroTag;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const _GlassFab({
    required this.heroTag,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient:
            active
                ? const LinearGradient(
                  colors: [_purple, _purpleDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.9),
                    Colors.white.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:
                active
                    ? _purple.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.05),
            blurRadius: active ? 12 : 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color:
              active
                  ? _purpleDark.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      child: FloatingActionButton.small(
        heroTag: heroTag,
        tooltip: tooltip,
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: active ? Colors.white : _purpleDark),
      ),
    );
  }
}
