import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart'
    as gpa;

import 'package:godavao/core/osrm_service.dart';
import 'package:godavao/core/reverse_geocoder.dart'; // <- add this

enum GeometryMode { osrm, manual }

class DriverRouteGeometryPage extends StatefulWidget {
  final String routeId;
  const DriverRouteGeometryPage({super.key, required this.routeId});

  @override
  State<DriverRouteGeometryPage> createState() =>
      _DriverRouteGeometryPageState();
}

class _DriverRouteGeometryPageState extends State<DriverRouteGeometryPage> {
  final _sb = Supabase.instance.client;
  final _map = MapController();

  // UI
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  // Mode
  GeometryMode _mode = GeometryMode.osrm;

  // OSRM
  LatLng? _start;
  LatLng? _end;
  Polyline? _osrmRoute;
  double? _osrmKm;
  double? _osrmMins;

  // Manual
  final List<LatLng> _manualPoints = [];
  Polyline? _manualRoute;
  double? _manualKm;

  // Addresses
  String? _startAddress;
  String? _endAddress;

  // small debounce to avoid spamming geocoder during quick edits
  Timer? _geocodeDebounce;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r =
          await _sb
              .from('driver_routes')
              .select('''
            route_mode, route_polyline, manual_polyline,
            start_lat, start_lng, end_lat, end_lng,
            start_address, end_address
          ''')
              .eq('id', widget.routeId)
              .single();

      final modeStr = (r['route_mode'] as String?) ?? 'osrm';
      _mode = modeStr == 'manual' ? GeometryMode.manual : GeometryMode.osrm;

      // start/end (if present)
      final sLat = (r['start_lat'] as num?)?.toDouble();
      final sLng = (r['start_lng'] as num?)?.toDouble();
      final eLat = (r['end_lat'] as num?)?.toDouble();
      final eLng = (r['end_lng'] as num?)?.toDouble();
      _start = (sLat != null && sLng != null) ? LatLng(sLat, sLng) : null;
      _end = (eLat != null && eLng != null) ? LatLng(eLat, eLng) : null;

      _startAddress = (r['start_address'] as String?)?.trim();
      _endAddress = (r['end_address'] as String?)?.trim();

      if (_mode == GeometryMode.osrm) {
        if (_start != null && _end != null) {
          try {
            _osrmRoute = await fetchOsrmRoute(start: _start!, end: _end!);
            final d = await fetchOsrmRouteDetailed(start: _start!, end: _end!);
            _osrmKm = d.distanceMeters / 1000.0;
            _osrmMins = d.durationSeconds / 60.0;
          } catch (_) {
            final saved = r['route_polyline'] as String?;
            if (saved != null && saved.isNotEmpty) {
              final coords = gpa.decodePolyline(saved);
              final pts =
                  coords
                      .map((e) => LatLng(e[0].toDouble(), e[1].toDouble()))
                      .toList();
              _osrmRoute =
                  pts.isEmpty
                      ? null
                      : Polyline(
                        points: pts,
                        strokeWidth: 4,
                        color: _purpleDark,
                      );
              _osrmKm = _distanceKm(pts);
              _osrmMins =
                  _osrmKm == null
                      ? null
                      : math.max((_osrmKm! / 22.0) * 60.0, 1.0);
            }
          }
        }
      } else {
        final saved = r['manual_polyline'] as String?;
        if (saved != null && saved.isNotEmpty) {
          final coords = gpa.decodePolyline(saved);
          _manualPoints
            ..clear()
            ..addAll(
              coords.map((e) => LatLng(e[0].toDouble(), e[1].toDouble())),
            );
        }
        if (_manualPoints.length >= 2) {
          _manualKm = _distanceKm(_manualPoints);
          _manualRoute = Polyline(
            points: List.of(_manualPoints),
            strokeWidth: 4,
            color: _purpleDark.withOpacity(.9),
          );
          // derive addresses from endpoints if missing
          _start ??= _manualPoints.first;
          _end ??= _manualPoints.last;
        }
      }

      // If we have coords but missing addresses, reverse-geocode once and write-back (best-effort).
      unawaited(_ensureAddressesWrittenBack());

      // Fit map
      final center =
          _start ??
          _end ??
          (_manualPoints.isNotEmpty
              ? _manualPoints.first
              : const LatLng(7.1907, 125.4553));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mode == GeometryMode.osrm && _start != null && _end != null) {
          _fitPoints([_start!, _end!]);
        } else if (_mode == GeometryMode.manual && _manualPoints.isNotEmpty) {
          _fitPoints(_manualPoints);
        } else {
          _map.move(center, 13);
        }
      });

      _dirty = false;
    } catch (e) {
      _error = 'Failed to load route geometry: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureAddressesWrittenBack() async {
    if (_start == null || _end == null) return;

    final needStart = (_startAddress == null || _startAddress!.isEmpty);
    final needEnd = (_endAddress == null || _endAddress!.isEmpty);
    if (!needStart && !needEnd) return;

    try {
      final s =
          needStart
              ? await reverseGeocodeText(_start!.latitude, _start!.longitude)
              : _startAddress;
      final e =
          needEnd
              ? await reverseGeocodeText(_end!.latitude, _end!.longitude)
              : _endAddress;

      if (!mounted) return;
      setState(() {
        _startAddress = (s?.isNotEmpty ?? false) ? s : _coordShort(_start);
        _endAddress = (e?.isNotEmpty ?? false) ? e : _coordShort(_end);
      });

      // best-effort write-back so future reads are instant
      await _sb
          .from('driver_routes')
          .update({
            if (s != null && s.isNotEmpty) 'start_address': s,
            if (e != null && e.isNotEmpty) 'end_address': e,
          })
          .eq('id', widget.routeId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _startAddress ??= _coordShort(_start);
        _endAddress ??= _coordShort(_end);
      });
    }
  }

  void _fitPoints(List<LatLng> pts) {
    if (pts.isEmpty) return;
    final b = LatLngBounds.fromPoints(pts);
    _map.fitCamera(
      CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(36)),
    );
  }

  double? _distanceKm(List<LatLng> pts) {
    if (pts.length < 2) return null;
    final d = Distance();
    double sum = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      sum += d.as(LengthUnit.Kilometer, pts[i], pts[i + 1]);
    }
    return sum;
  }

  String _coordShort(LatLng? p) =>
      p == null
          ? 'Unknown'
          : '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';

  /* ============== Interactions ============== */

  void _onTap(TapPosition _, LatLng p) async {
    if (_mode != GeometryMode.manual) return;
    setState(() {
      _manualPoints.add(p);
      _manualRoute = Polyline(
        points: List.of(_manualPoints),
        strokeWidth: 4,
        color: _purpleDark.withOpacity(.9),
      );
      _manualKm = _distanceKm(_manualPoints);
      _dirty = true;
    });

    // update addresses from endpoints when user starts/extends manual polyline
    _start = _manualPoints.first;
    _end = _manualPoints.length > 1 ? _manualPoints.last : null;
    _debouncedReverseGeocode();
  }

  void _onLongPress(TapPosition _, LatLng p) async {
    if (_mode == GeometryMode.osrm) {
      if (_start == null) {
        setState(() {
          _start = p;
          _end = null;
          _osrmRoute = null;
          _osrmKm = null;
          _osrmMins = null;
          _dirty = true;
        });
        _debouncedReverseGeocode(); // new start
        return;
      }
      if (_end == null) {
        setState(() => _end = p);
        try {
          final poly = await fetchOsrmRoute(start: _start!, end: _end!);
          final detail = await fetchOsrmRouteDetailed(
            start: _start!,
            end: _end!,
          );
          setState(() {
            _osrmRoute = poly;
            _osrmKm = detail.distanceMeters / 1000.0;
            _osrmMins = detail.durationSeconds / 60.0;
            _dirty = true;
          });
          _fitPoints([_start!, _end!]);
          _debouncedReverseGeocode(); // have both; get both addresses
        } catch (e) {
          setState(() => _error = 'OSRM failed: $e');
        }
        return;
      }
      // third long-press resets start (and route)
      setState(() {
        _start = p;
        _end = null;
        _osrmRoute = null;
        _osrmKm = null;
        _osrmMins = null;
        _dirty = true;
      });
      _debouncedReverseGeocode();
    } else {
      // Manual quick actions
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
                      onPressed: () {
                        Navigator.pop(context);
                        if (_manualPoints.isNotEmpty) {
                          setState(() {
                            _manualPoints.removeLast();
                            _manualKm = _distanceKm(_manualPoints);
                            _manualRoute =
                                _manualPoints.length >= 2
                                    ? Polyline(
                                      points: List.of(_manualPoints),
                                      strokeWidth: 4,
                                      color: _purpleDark.withOpacity(.9),
                                    )
                                    : null;
                            _start =
                                _manualPoints.isNotEmpty
                                    ? _manualPoints.first
                                    : null;
                            _end =
                                _manualPoints.length > 1
                                    ? _manualPoints.last
                                    : null;
                            _dirty = true;
                          });
                          _debouncedReverseGeocode();
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
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _manualPoints.clear();
                          _manualKm = 0;
                          _manualRoute = null;
                          _start = null;
                          _end = null;
                          _startAddress = null;
                          _endAddress = null;
                          _dirty = true;
                        });
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

  void _debouncedReverseGeocode() {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 250), () async {
      // Only geocode for points we have
      try {
        if (_start != null) {
          final s = await reverseGeocodeText(
            _start!.latitude,
            _start!.longitude,
          );
          if (mounted) {
            setState(
              () =>
                  _startAddress =
                      (s.isNotEmpty ?? false) ? s : _coordShort(_start),
            );
          }
        }
        if (_end != null) {
          final e = await reverseGeocodeText(_end!.latitude, _end!.longitude);
          if (mounted) {
            setState(
              () =>
                  _endAddress = (e.isNotEmpty ?? false) ? e : _coordShort(_end),
            );
          }
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _startAddress ??= _coordShort(_start);
          _endAddress ??= _coordShort(_end);
        });
      }
    });
  }

  /* ============== Save ============== */

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String modeStr = _mode == GeometryMode.osrm ? 'osrm' : 'manual';
      String? routePolyline;
      String? manualPolyline;
      double? sLat, sLng, eLat, eLng;

      if (_mode == GeometryMode.osrm) {
        if (_start == null || _end == null || _osrmRoute == null) {
          throw 'In OSRM mode, set START and DESTINATION (long-press).';
        }
        final coords =
            _osrmRoute!.points.map((p) => [p.latitude, p.longitude]).toList();
        routePolyline = gpa.encodePolyline(coords);
        sLat = _start!.latitude;
        sLng = _start!.longitude;
        eLat = _end!.latitude;
        eLng = _end!.longitude;
        manualPolyline = null; // clear manual
      } else {
        if (_manualPoints.length < 2) {
          throw 'In Manual mode, tap at least two points on the map.';
        }
        final coords =
            _manualPoints.map((p) => [p.latitude, p.longitude]).toList();
        manualPolyline = gpa.encodePolyline(coords);
        sLat = _manualPoints.first.latitude;
        sLng = _manualPoints.first.longitude;
        eLat = _manualPoints.last.latitude;
        eLng = _manualPoints.last.longitude;
        routePolyline = null; // clear osrm
      }

      // Make sure we have addresses to save (best-effort)
      String? startAddr = _startAddress;
      String? endAddr = _endAddress;
      try {
        if ((startAddr == null || startAddr.isEmpty)) {
          startAddr = await reverseGeocodeText(sLat, sLng);
        }
        if ((endAddr == null || endAddr.isEmpty)) {
          endAddr = await reverseGeocodeText(eLat, eLng);
        }
      } catch (_) {
        // fall through with whatever we have
      }

      await _sb
          .from('driver_routes')
          .update({
            'route_mode': modeStr,
            'route_polyline': routePolyline,
            'manual_polyline': manualPolyline,
            'start_lat': sLat,
            'start_lng': sLng,
            'end_lat': eLat,
            'end_lng': eLng,
            'start_address': startAddr, // <- save
            'end_address': endAddr, // <-
          })
          .eq('id', widget.routeId);

      if (!mounted) return;
      _dirty = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Geometry saved')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty || _saving) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved geometry changes.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    return leave == true;
  }

  /* ============== UI ============== */

  @override
  Widget build(BuildContext context) {
    final mapCenter =
        _start ??
        _end ??
        (_manualPoints.isNotEmpty
            ? _manualPoints.first
            : const LatLng(7.1907, 125.4553));

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Geometry'),
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Fit',
              onPressed: () {
                if (_mode == GeometryMode.osrm &&
                    _start != null &&
                    _end != null) {
                  _fitPoints([_start!, _end!]);
                } else if (_mode == GeometryMode.manual &&
                    _manualPoints.isNotEmpty) {
                  _fitPoints(_manualPoints);
                }
              },
              icon: const Icon(Icons.fullscreen),
            ),
            IconButton(
              tooltip: 'Reload',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _saving ? null : _save,
          icon:
              _saving
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                  : const Icon(Icons.save),
          label: Text(_saving ? 'Saving…' : 'Save'),
          backgroundColor: _purple,
          foregroundColor: Colors.white,
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                  children: [
                    _ModeToggle(
                      mode: _mode,
                      onChanged: (m) {
                        if (_mode == m) return;
                        setState(() {
                          _mode = m;
                          _error = null;
                          _dirty = true;
                        });
                      },
                    ),
                    // hint row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: _InfoRow(
                        icon:
                            _mode == GeometryMode.osrm
                                ? Icons.touch_app
                                : Icons.edit,
                        text:
                            _mode == GeometryMode.osrm
                                ? (_start == null
                                    ? 'Long-press map to set START'
                                    : _end == null
                                    ? 'Long-press to set DESTINATION'
                                    : 'Long-press again to reset START')
                                : 'Tap to add points • Long-press for Undo/Clear',
                      ),
                    ),
                    // address chips
                    if (_mode == GeometryMode.osrm || _manualPoints.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _AddressChip(
                              label: 'Start',
                              value: _startAddress ?? _coordShort(_start),
                            ),
                            _AddressChip(
                              label: 'End',
                              value: _endAddress ?? _coordShort(_end),
                            ),
                          ],
                        ),
                      ),
                    // stats
                    if (_mode == GeometryMode.osrm)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                icon: Icons.straighten,
                                label: 'Distance',
                                value:
                                    _osrmKm == null
                                        ? '—'
                                        : '${_osrmKm!.toStringAsFixed(1)} km',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatCard(
                                icon: Icons.timer,
                                label: 'Duration',
                                value:
                                    _osrmMins == null
                                        ? '—'
                                        : '${_osrmMins!.toStringAsFixed(0)} min',
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: _StatCard(
                          icon: Icons.timeline,
                          label: 'Distance',
                          value:
                              _manualKm == null
                                  ? '—'
                                  : '${_manualKm!.toStringAsFixed(1)} km',
                        ),
                      ),
                    Expanded(
                      child: FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: mapCenter,
                          initialZoom: 13,
                          onTap: _onTap,
                          onLongPress: _onLongPress,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.godavao.app',
                          ),
                          if (_mode == GeometryMode.osrm && _osrmRoute != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _osrmRoute!.points,
                                  strokeWidth: 4,
                                  color: _purpleDark.withOpacity(.9),
                                ),
                              ],
                            ),
                          if (_mode == GeometryMode.manual &&
                              _manualRoute != null)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _manualRoute!.points,
                                  strokeWidth: 4,
                                  color: _purpleDark.withOpacity(.9),
                                ),
                              ],
                            ),
                          if (_mode == GeometryMode.osrm && _start != null)
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
                          if (_mode == GeometryMode.osrm && _end != null)
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
                          if (_mode == GeometryMode.manual &&
                              _manualPoints.isNotEmpty)
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
                      Container(
                        width: double.infinity,
                        color: Colors.red.shade50,
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}

/* ===== Small UI bits ===== */

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final GeometryMode mode;
  final ValueChanged<GeometryMode> onChanged;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children:
            GeometryMode.values.map((m) {
              final selected = m == mode;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient:
                        selected
                            ? const LinearGradient(
                              colors: [_purple, _purpleDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                            : const LinearGradient(
                              colors: [Colors.white, Colors.white],
                            ),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color:
                          selected
                              ? Colors.transparent
                              : _purple.withOpacity(0.3),
                    ),
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: _purple.withOpacity(0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: () => onChanged(m),
                    child: Center(
                      child: Text(
                        m == GeometryMode.osrm ? 'OSRM' : 'Manual',
                        style: TextStyle(
                          color: selected ? Colors.white : _purpleDark,
                          fontWeight: FontWeight.w700,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == 'Start' ? Icons.location_on : Icons.flag,
            size: 14,
            color: Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
