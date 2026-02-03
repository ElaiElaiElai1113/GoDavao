import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LivePublisher {
  LivePublisher(
    this.sb, {
    required this.userId,
    required this.rideId,
    required this.actor, // 'driver' | 'passenger'
    this.minMeters = 8,
    this.minHeadingDelta = 10,
    this.minPeriod = const Duration(seconds: 3),
    this.traceEveryMeters = 50,
    this.locationAccuracy = LocationAccuracy.best,
    this.distanceFilter = 3,
  });

  final SupabaseClient sb;
  String userId; // still useful for RLS/ownership, but not the conflict key
  String rideId;
  String actor;

  final double minMeters;
  final double minHeadingDelta;
  final Duration minPeriod;
  final double traceEveryMeters;
  final LocationAccuracy locationAccuracy;
  final int distanceFilter;

  StreamSubscription<Position>? _sub;
  Position? _lastPos;
  double? _lastHeading;
  DateTime? _lastSentAt;
  double _sinceLastTraceMeters = 0;
  Object? lastError;

  bool get isRunning => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      lastError = 'Location services are disabled';
      throw lastError!;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      lastError = 'Location permission denied';
      throw lastError!;
    }

    final settings = LocationSettings(
      accuracy: locationAccuracy,
      distanceFilter: distanceFilter,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        try {
          if (!_shouldSend(pos)) return;

          final movedMeters =
              _lastPos == null
                  ? 0.0
                  : _haversine(
                    _lastPos!.latitude,
                    _lastPos!.longitude,
                    pos.latitude,
                    pos.longitude,
                  );

          _sinceLastTraceMeters += movedMeters;
          _lastPos = pos;

          if (!pos.heading.isNaN) _lastHeading = pos.heading;
          _lastSentAt = DateTime.now();

          final speed = pos.speed.isNaN ? null : pos.speed;
          final heading = (_lastHeading?.isNaN ?? true) ? null : _lastHeading;

          // ⬇️ key change: onConflict 'ride_id,actor'
          await sb.from('live_locations').upsert({
            'ride_id': rideId,
            'actor': actor,
            'user_id': userId, // still stored for RLS/audit
            'lat': pos.latitude,
            'lng': pos.longitude,
            'speed_mps': speed,
            'heading': heading,
            'updated_at': _lastSentAt!.toUtc().toIso8601String(),
          }, onConflict: 'ride_id,actor');

          if (_sinceLastTraceMeters >= traceEveryMeters) {
            _sinceLastTraceMeters = 0;
            await sb.from('location_traces').insert({
              'ride_id': rideId,
              'actor': actor,
              'user_id': userId,
              'lat': pos.latitude,
              'lng': pos.longitude,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        } catch (e) {
          lastError = e;
        }
      },
      onError: (Object e, _) => lastError = e,
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _lastPos = null;
    _lastHeading = null;
    _lastSentAt = null;
    _sinceLastTraceMeters = 0;
  }

  Future<void> switchRide({
    required String newRideId,
    required String newActor,
  }) async {
    final wasRunning = isRunning;
    if (wasRunning) await stop();
    rideId = newRideId;
    actor = newActor;
    if (wasRunning) await start();
  }

  Future<void> switchUser(String newUserId) async {
    final wasRunning = isRunning;
    if (wasRunning) await stop();
    userId = newUserId;
    if (wasRunning) await start();
  }

  bool _shouldSend(Position pos) {
    if (_lastSentAt != null &&
        DateTime.now().difference(_lastSentAt!) < minPeriod) {
      return false;
    }
    if (_lastPos == null) return true;

    final moved = _haversine(
      _lastPos!.latitude,
      _lastPos!.longitude,
      pos.latitude,
      pos.longitude,
    );
    final headingNow = pos.heading.isNaN ? (_lastHeading ?? 0) : pos.heading;
    final headingDelta = _deltaAngle(_lastHeading ?? 0, headingNow);

    return moved >= minMeters || headingDelta >= minHeadingDelta;
  }

  double _deltaAngle(double a, double b) {
    final d = ((b - a + 540) % 360) - 180;
    return d.abs();
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final s1 = math.sin(dLat / 2), s2 = math.sin(dLon / 2);
    final a =
        s1 * s1 +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            s2 *
            s2;
    return 2 * R * math.asin(math.sqrt(a));
  }
}
