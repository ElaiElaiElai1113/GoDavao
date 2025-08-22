import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

class LiveSubscriber {
  final SupabaseClient sb;
  final String userId; // the user we follow
  final void Function(LatLng pos, double? heading) onUpdate;

  RealtimeChannel? _chan;

  LiveSubscriber(this.sb, {required this.userId, required this.onUpdate});

  void listen() {
    _chan =
        sb.channel('live_locations_user_$userId')
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.insert,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: _handle, // 👈 no type on the function
          )
          ..onPostgresChanges(
            schema: 'public',
            table: 'live_locations',
            event: PostgresChangeEvent.update,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: _handle,
          )
          ..subscribe();

    _seed();
  }

  // Accept dynamic so it works with both v1 and v2 payload types
  void _handle(dynamic payload) {
    final row = payload.newRecord ?? payload.oldRecord;
    if (row == null) return;

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
            .eq('user_id', userId)
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
