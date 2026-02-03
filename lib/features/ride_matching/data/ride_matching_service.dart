import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

class RideMatchService {
  final supabase = Supabase.instance.client;
  final Distance distance = const Distance();

  Future<Map<String, dynamic>?> matchRideRequest({
    required String rideRequestId,
    required LatLng pickup,
    required LatLng destination,
  }) async {
    final drivers = await supabase
        .from('driver_routes')
        .select('id, driver_id, start_lat, start_lng, end_lat, end_lng');

    for (final driver in drivers) {
      final start = LatLng((driver['start_lat'] as num?)?.toDouble() ?? 0.0, (driver['start_lng'] as num?)?.toDouble() ?? 0.0);
      final end = LatLng((driver['end_lat'] as num?)?.toDouble() ?? 0.0, (driver['end_lng'] as num?)?.toDouble() ?? 0.0);

      final pickupDistance = distance.as(LengthUnit.Kilometer, pickup, start);
      final destinationDistance = distance.as(
        LengthUnit.Kilometer,
        destination,
        end,
      );

      if (pickupDistance <= 3 && destinationDistance <= 3) {
        await supabase.from('ride_matches').insert({
          'ride_request_id': rideRequestId,
          'driver_route_id': driver['id'],
          'driver_id': driver['driver_id'],
        });

        final driverInfo =
            await supabase
                .from('users')
                .select('id, name')
                .eq('id', driver['driver_id'] as String)
                .single();

        return driverInfo;
      }
    }

    return null;
  }
}
