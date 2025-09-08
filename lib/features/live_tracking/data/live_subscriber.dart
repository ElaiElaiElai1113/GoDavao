import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

class LiveSubscriber {
  final SupabaseClient sb;
  final String rideId;
  final String actor; // 'driver' or 'passenger' — WHO you want to follow
  final void Function(LatLng pos, double? heading) onUpdate;

  RealtimeChannel? _chan;

  LiveSubscriber(
    this.sb, {
    required this.rideId,
    required this.actor,
    required this.onUpdate,
  });

  void listen() {
    _chan =
        sb.channel('live_locations:$rideId:$actor')
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.insert,
            callback: _handle,
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.update,
            callback: _handle,
          )
          ..subscribe();

    _seed();
  }

  void _handle(dynamic payload) {
    // v2: payload.newRecord (Map), v1: Map-like as well
    final row = payload.newRecord ?? payload.oldRecord;
    if (row == null) return;

    if (row['ride_id']?.toString() != rideId) return;
    if (row['actor']?.toString() != actor) return;

    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    onUpdate(LatLng(lat, lng), (row['heading'] as num?)?.toDouble());
  }

  Future<void> _seed() async {
    final res =
        await sb
            .from('live_locations')
            .select('lat,lng,heading')
            .eq('ride_id', rideId)
            .eq('actor', actor)
            .maybeSingle();

    if (res != null) {
      final lat = (res['lat'] as num?)?.toDouble();
      final lng = (res['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        onUpdate(LatLng(lat, lng), (res['heading'] as num?)?.toDouble());
      }
    }
  }

  void dispose() {
    if (_chan != null) sb.removeChannel(_chan!);
  }
}
