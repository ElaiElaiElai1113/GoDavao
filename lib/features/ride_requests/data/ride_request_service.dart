import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/ride_requests/models/ride_request_model.dart';

class RideRequestService {
  final _supabase = Supabase.instance.client;

  Future<String> saveRideRequest(RideRequest r) async {
    final resp =
        await _supabase
            .from('ride_requests')
            .insert(r.toMap())
            .select('id')
            .single();
    return resp['id'] as String;
  }

  /// Existing matching logic updated to use driver_route_id
  Future<void> matchRideRequest({required String rideRequestId}) async {
    final r =
        await _supabase
            .from('ride_requests')
            .select('driver_route_id')
            .eq('id', rideRequestId)
            .single();
    final routeId = r['driver_route_id'] as String;

    final route =
        await _supabase
            .from('driver_routes')
            .select('driver_id')
            .eq('id', routeId)
            .single();
    final driverId = route['driver_id'] as String;

    await _supabase.from('ride_matches').insert({
      'ride_request_id': rideRequestId,
      'driver_route_id': routeId,
      'driver_id': driverId,
      'status': 'pending',
    });
  }
}
