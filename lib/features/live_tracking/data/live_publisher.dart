import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Publishes live location for a single user (driver or passenger).
/// Schema expectations:
///   live_locations:
///     user_id (PK or UNIQUE), ride_id, actor, lat, lng, speed_mps, heading, updated_at
///   location_traces (optional breadcrumbs):
///     user_id, ride_id, actor, lat, lng, recorded_at
///
/// Ensure a unique constraint exists on live_locations.user_id
/// so `onConflict: 'user_id'` works correctly.
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

  /// Identifies the row to upsert; make sure live_locations has UNIQUE/PK on this.
  String userId;

  /// Current ride association for this publisher.
  String rideId;

  /// 'driver' or 'passenger'
  String actor;

  // Tunables
  final double minMeters; // Minimum movement before sending (meters)
  final double
  minHeadingDelta; // Minimum heading change before sending (degrees)
  final Duration minPeriod; // Min time between sends
  final double traceEveryMeters; // Spacing for breadcrumb inserts
  final LocationAccuracy locationAccuracy; // Geolocator accuracy
  final int distanceFilter; // Raw stream distance filter (meters)

  StreamSubscription<Position>? _sub;
  Position? _lastPos;
  double? _lastHeading;
  DateTime? _lastSentAt;
  double _sinceLastTraceMeters = 0;

  Object? lastError;

  bool get isRunning => _sub != null;

  /// Starts streaming and publishing locations. Idempotent.
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

    // You can switch to AndroidSettings/iOSSettings if you want platform-specific configs.
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

          // Heading can be NaN on some devices; hold the last good value.
          if (!pos.heading.isNaN) {
            _lastHeading = pos.heading;
          }
          _lastSentAt = DateTime.now();

          // Sanitize NaNs → nulls
          final speed = pos.speed.isNaN ? null : pos.speed;
          final heading = (_lastHeading?.isNaN ?? true) ? null : _lastHeading;

          // Upsert the single "live" row
          await sb.from('live_locations').upsert({
            'user_id': userId,
            'ride_id': rideId,
            'actor': actor,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'speed_mps': speed,
            'heading': heading,
            'updated_at': _lastSentAt!.toUtc().toIso8601String(),
          }, onConflict: 'user_id');

          // Optional breadcrumb every X meters
          if (_sinceLastTraceMeters >= traceEveryMeters) {
            _sinceLastTraceMeters = 0;
            await sb.from('location_traces').insert({
              'user_id': userId,
              'ride_id': rideId,
              'actor': actor,
              'lat': pos.latitude,
              'lng': pos.longitude,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        } catch (e) {
          // Best-effort: don't crash the stream; stash error for diagnostics.
          lastError = e;
        }
      },
      onError: (e, _) => lastError = e,
      cancelOnError: false,
    );
  }

  /// Stops streaming and resets internal state. Idempotent.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _lastPos = null;
    _lastHeading = null;
    _lastSentAt = null;
    _sinceLastTraceMeters = 0;
  }

  /// Switch rides (and/or actor) safely. If running, restarts stream.
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

  /// Optional: switch user (rare; only if you truly need it).
  Future<void> switchUser(String newUserId) async {
    final wasRunning = isRunning;
    if (wasRunning) await stop();
    userId = newUserId;
    if (wasRunning) await start();
  }

  // ---------------- Internals ----------------

  bool _shouldSend(Position pos) {
    // Time gate
    if (_lastSentAt != null) {
      final since = DateTime.now().difference(_lastSentAt!);
      if (since < minPeriod) return false;
    }
    // First fix always allowed
    if (_lastPos == null) return true;

    // Distance / heading gate
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
    // shortest angular distance in degrees
    final d = ((b - a + 540) % 360) - 180;
    return d.abs();
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // meters
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
