import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class LiveSubscriber {
  final SupabaseClient sb;
  final String rideId;
  final void Function(LatLng pos, double? heading) onUpdate;

  RealtimeChannel? _chan;

  LiveSubscriber(this.sb, {required this.rideId, required this.onUpdate});

  void listenDriver() {
    _chan =
        sb.channel('live_locations:$rideId')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'live_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'ride_id',
              value: rideId,
            ),
            callback: (payload) {
              final row = payload.newRecord ?? payload.oldRecord;
              if (row == null) return;
              if ((row['actor'] as String?) != 'driver') return;
              onUpdate(
                LatLng(row['lat'] as double, row['lng'] as double),
                (row['heading'] as num?)?.toDouble(),
              );
            },
          )
          ..subscribe();

    // seed (pull latest)
    _fetchSeed();
  }

  Future<void> _fetchSeed() async {
    final res =
        await sb
            .from('live_locations')
            .select('lat,lng,heading')
            .eq('ride_id', rideId)
            .eq('actor', 'driver')
            .maybeSingle();
    if (res != null) {
      onUpdate(
        LatLng((res['lat'] as num).toDouble(), (res['lng'] as num).toDouble()),
        (res['heading'] as num?)?.toDouble(),
      );
    }
  }

  void dispose() {
    if (_chan != null) sb.removeChannel(_chan!);
  }
}
