import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LivePublisher {
  final SupabaseClient sb;
  final String rideId;
  final String actor; // 'driver' | 'passenger'
  StreamSubscription<Position>? _sub;

  LivePublisher(this.sb, {required this.rideId, required this.actor});

  Future<void> start() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw 'Location permission denied';
    }

    // Faster when near pickup, slower en-route; tune as needed
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      try {
        await sb.from('live_locations').upsert({
          'ride_id': rideId,
          'actor': actor,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'speed_mps': pos.speed,
          'heading': pos.heading,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });

        // optional breadcrumb every ~50m
        if ((pos.speed) > 3) {
          await sb.from('location_traces').insert({
            'ride_id': rideId,
            'actor': actor,
            'lat': pos.latitude,
            'lng': pos.longitude,
          });
        }
      } catch (_) {
        /* swallow non-fatal */
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
