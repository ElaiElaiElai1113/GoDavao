import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _dirty = false;

  LatLng? _start;
  LatLng? _end;

  static const _purple = Color(0xFF6A27F7);

  @override
  void initState() {
    super.initState();
    _load();
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
              .select('start_lat, start_lng, end_lat, end_lng')
              .eq('id', widget.routeId)
              .single();

      final sLat = (r['start_lat'] as num?)?.toDouble();
      final sLng = (r['start_lng'] as num?)?.toDouble();
      final eLat = (r['end_lat'] as num?)?.toDouble();
      final eLng = (r['end_lng'] as num?)?.toDouble();

      _start = (sLat != null && sLng != null) ? LatLng(sLat, sLng) : null;
      _end = (eLat != null && eLng != null) ? LatLng(eLat, eLng) : null;

      if (_start == null || _end == null) {
        // default center (Davao)
        _start ??= const LatLng(7.1907, 125.4553);
        _end ??= const LatLng(7.0907, 125.5553);
      }
      _dirty = false;

      // fit on first load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final b = LatLngBounds.fromPoints([_start!, _end!]);
        _map.fitCamera(
          CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(36)),
        );
      });
    } catch (e) {
      _error = 'Failed to load geometry: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _save() async {
    if (_start == null || _end == null) return;
    setState(() => _saving = true);
    try {
      await _sb
          .from('driver_routes')
          .update({
            'start_lat': _start!.latitude,
            'start_lng': _start!.longitude,
            'end_lat': _end!.latitude,
            'end_lng': _end!.longitude,
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

  @override
  Widget build(BuildContext context) {
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
                if (_start != null && _end != null) {
                  final b = LatLngBounds.fromPoints([_start!, _end!]);
                  _map.fitCamera(
                    CameraFit.bounds(
                      bounds: b,
                      padding: const EdgeInsets.all(36),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.fullscreen),
            ),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : Column(
                  children: [
                    Expanded(
                      child: FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: _start!,
                          initialZoom: 13,
                          onTap: (_, __) {}, // keep map interactive
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.godavao.app',
                          ),
                          PolylineLayer(
                            polylines: [
                              if (_start != null && _end != null)
                                Polyline(
                                  points: [_start!, _end!],
                                  strokeWidth: 4,
                                  color: Colors.deepPurpleAccent,
                                ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              if (_start != null)
                                Marker(
                                  point: _start!,
                                  width: 36,
                                  height: 36,
                                  child: _draggablePin(
                                    icon: Icons.place,
                                    color: Colors.green,
                                    onDragEnd: (p) {
                                      setState(() {
                                        _start = p;
                                        _dirty = true;
                                      });
                                    },
                                  ),
                                ),
                              if (_end != null)
                                Marker(
                                  point: _end!,
                                  width: 36,
                                  height: 36,
                                  child: _draggablePin(
                                    icon: Icons.flag,
                                    color: Colors.red,
                                    onDragEnd: (p) {
                                      setState(() {
                                        _end = p;
                                        _dirty = true;
                                      });
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      color: Colors.white,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.undo),
                              label: const Text('Reset'),
                              onPressed:
                                  _loading
                                      ? null
                                      : () {
                                        _load();
                                      },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.save),
                              onPressed: _saving ? null : _save,
                              label: Text(_saving ? 'Saving…' : 'Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  // A simple draggable "pin": we simulate drag by opening a tiny drag overlay map picker.
  // (FlutterMap Marker isn't directly draggable; for full drag, use a DraggableLayer plugin.
  // This lightweight approach keeps dependencies minimal.)
  Widget _draggablePin({
    required IconData icon,
    required Color color,
    required ValueChanged<LatLng> onDragEnd,
  }) {
    return GestureDetector(
      onLongPress: () async {
        final updated = await _openMiniPicker();
        if (updated != null) onDragEnd(updated);
      },
      child: Icon(icon, color: color, size: 30),
    );
  }

  Future<LatLng?> _openMiniPicker() async {
    LatLng center = _map.camera.center;
    return showDialog<LatLng>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        final c = MapController();
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: MediaQuery.of(context).size.width * .9,
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: c,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 15,
                    onPositionChanged: (p, _) => center = p.center ?? center,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.godavao.app',
                    ),
                  ],
                ),
                const Center(
                  child: Icon(
                    Icons.gps_fixed,
                    size: 28,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, center),
              child: const Text('Use here'),
            ),
          ],
        );
      },
    );
  }
}
