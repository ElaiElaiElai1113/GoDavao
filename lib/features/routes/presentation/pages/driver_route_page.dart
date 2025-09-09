import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/core/fare_service.dart';
import 'package:godavao/main.dart' show localNotify;

// Update paths if needed
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
  final FareService _fareService = FareService(); // uses your defaults
  static const double _platformFeePct = 0.15; // 15% platform/service fee

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

  // Styles
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkHasVehicles();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
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
      if (_mode == RouteMode.osrm) {
        if (_start == null || _end == null) {
          _clearFare();
          return;
        }
        final f = await _fareService.estimate(
          pickup: _start!,
          destination: _end!,
        );
        final net = (f.total * (1 - _platformFeePct)).roundToDouble();
        if (!mounted) return;
        setState(() {
          _fare = f;
          _driverNet = net;
        });
      } else {
        if (_manualPoints.length < 2) {
          _clearFare();
          return;
        }
        final rules = _fareService.rules;
        final km = _manualKm ?? _pathKm(_manualPoints);
        const avgKmh = 22.0;
        final mins = math.max((km / avgKmh) * 60.0, 1.0);

        double subtotal =
            rules.baseFare +
            (rules.perKm * km) +
            (rules.perMin * mins) +
            rules.bookingFee;
        subtotal = math.max(subtotal, rules.minFare);

        bool isNight() {
          final now = DateTime.now();
          final h = now.hour;
          if (rules.nightStartHour <= rules.nightEndHour) {
            return h >= rules.nightStartHour && h <= rules.nightEndHour;
          } else {
            return h >= rules.nightStartHour || h <= rules.nightEndHour;
          }
        }

        final surcharge = isNight() ? subtotal * rules.nightSurchargePct : 0.0;
        final total = (subtotal + surcharge).roundToDouble();

        final f = FareBreakdown(
          distanceKm: double.parse(km.toStringAsFixed(2)),
          durationMin: double.parse(mins.toStringAsFixed(0)),
          subtotal: double.parse(subtotal.toStringAsFixed(2)),
          surcharge: double.parse(surcharge.toStringAsFixed(2)),
          total: total,
        );
        final net = (f.total * (1 - _platformFeePct)).roundToDouble();

        if (!mounted) return;
        setState(() {
          _fare = f;
          _driverNet = net;
        });
      }
    } catch (_) {
      _clearFare();
    }
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
          color: Colors.blue,
        );
      });
      await _recomputeFareEstimate();
    }
  }

  /// OSRM: long-press 1) set start  2) set end (+fetch)  3) reset with new start
  /// Manual: long-press opens Undo / Clear
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
      showModalBottomSheet(
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
                                      color: Colors.blue,
                                    )
                                    : null;
                          });
                          await _recomputeFareEstimate();
                        }
                      },
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
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                      onPressed: () => Navigator.pop(context),
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
        'route_polyline': routePolyline, // set in OSRM mode
        'manual_polyline': manualPolyline, // set in Manual mode
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

  @override
  Widget build(BuildContext context) {
    final center = _start ?? const LatLng(7.1907, 125.4553); // Davao

    String _fareLine() {
      if (_fare == null) return '—';
      return '₱${_fare!.total.toStringAsFixed(0)} '
          '(${_fare!.distanceKm.toStringAsFixed(1)} km'
          '${_mode == RouteMode.osrm && _osrmMins != null ? ', ${_fare!.durationMin.toStringAsFixed(0)} min' : ''})';
    }

    String _driverNetLine() {
      if (_driverNet == null) return '—';
      final pct = (_platformFeePct * 100).toStringAsFixed(0);
      return '₱${_driverNet!.toStringAsFixed(0)} (after $pct% fee)';
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Create Driver Route'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SegmentedButton<RouteMode>(
                  segments: const [
                    ButtonSegment(value: RouteMode.osrm, label: Text('OSRM')),
                    ButtonSegment(
                      value: RouteMode.manual,
                      label: Text('Manual'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) async {
                    setState(() {
                      _mode = s.first;
                      _error = null;
                    });
                    await _recomputeFareEstimate();
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                center: center,
                zoom: 13,
                onTap: _onMapTap,
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourcompany.godavao',
                ),
                if (_mode == RouteMode.osrm && _osrmRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _osrmRoute!.points,
                        strokeWidth: 4,
                        color: Colors.purple.shade700,
                      ),
                    ],
                  ),
                if (_mode == RouteMode.manual && _manualRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _manualRoute!.points,
                        strokeWidth: 4,
                        color: Colors.blue,
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

          if (_error != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.red.shade100,
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
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hint + in-sheet toggle (no overflow)
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app,
                          size: 18,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _mode == RouteMode.osrm
                                ? (_start == null
                                    ? 'Long-press to set START'
                                    : _end == null
                                    ? 'Long-press to set DESTINATION'
                                    : 'Long-press again to reset START')
                                : 'Tap to add points. Long-press for Undo/Clear.',
                            style: const TextStyle(color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: SegmentedButton<RouteMode>(
                              segments: const [
                                ButtonSegment(
                                  value: RouteMode.osrm,
                                  label: Text('Fastest'),
                                ),
                                ButtonSegment(
                                  value: RouteMode.manual,
                                  label: Text('Manual'),
                                ),
                              ],
                              selected: {_mode},
                              onSelectionChanged: (s) async {
                                setState(() {
                                  _mode = s.first;
                                  _error = null;
                                });
                                await _recomputeFareEstimate();
                              },
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Vehicle area
                    if (_checkingVehicles)
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
                    else if (!_hasAnyVehicle)
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
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VehicleForm(),
                                ),
                              );
                              await _checkHasVehicles();
                            },
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vehicle',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          VehicleSwitcher(
                            onChanged: (vehicle) async {
                              setState(() {
                                _vehicleId = vehicle['id'] as String?;
                                _vehicleSeats = (vehicle['seats'] as int?) ?? 0;
                              });
                              await _recomputeFareEstimate();
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Seats'),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  _vehicleSeats == null
                                      ? '—'
                                      : '${_vehicleSeats!} seats',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                    const SizedBox(height: 8),

                    // Distance / ETA
                    if (_mode == RouteMode.osrm && _osrmRoute != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.route,
                            size: 16,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_osrmKm == null ? '—' : _osrmKm!.toStringAsFixed(1)} km • '
                            '${_osrmMins == null ? '—' : _osrmMins!.toStringAsFixed(0)} min',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      )
                    else if (_mode == RouteMode.manual && _manualRoute != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.brush,
                            size: 16,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_manualKm?.toStringAsFixed(1) ?? '—'} km (manual)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),

                    const SizedBox(height: 6),

                    // Fare + driver net
                    Row(
                      children: [
                        const Icon(
                          Icons.local_taxi,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Estimated Fare: ${_fareLine()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Driver Net: ${_driverNetLine()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Meta
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _decor(
                        label: 'Route name (optional)',
                        hint: 'e.g., Morning Commute',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: _decor(
                        label: 'Notes (optional)',
                        hint: 'e.g., Prefers back roads',
                      ),
                      maxLines: 2,
                    ),

                    const SizedBox(height: 12),

                    // Publish
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
                                  : const Icon(
                                    Icons.publish,
                                    color: Colors.white,
                                  ),
                          label: Text(
                            _publishing ? 'Publishing…' : 'Publish Route',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          onPressed: _publishing ? null : _publish,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
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
