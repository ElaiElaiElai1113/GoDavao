import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_route_model.dart';

class RoutesService {
  final SupabaseClient _sb;
  RoutesService(this._sb);
  Future<void> saveRoute(DriverRoute route) async {
    await _sb.from('driver_routes').insert(route.toMap());
  }

  /// Updates route metadata (name/notes/vehicle/seats/etc.), without changing is_active.
  Future<void> updateRouteFields({
    required String routeId,
    String? name,
    String? notes,
    String? vehicleId,
    int? capacityTotal,
    int? capacityAvailable,
    String? routeMode,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name.isEmpty ? null : name;
    if (notes != null) payload['notes'] = notes.isEmpty ? null : notes;
    if (vehicleId != null) payload['vehicle_id'] = vehicleId;
    if (capacityTotal != null) payload['capacity_total'] = capacityTotal;
    if (capacityAvailable != null)
      payload['capacity_available'] = capacityAvailable;
    if (routeMode != null) payload['route_mode'] = routeMode;

    if (payload.isEmpty) return;

    await _sb
        .from('driver_routes')
        .update(payload)
        .eq('id', routeId)
        .select()
        .single();
  }

  /// Atomic cancel + notify + deactivate on the server.
  Future<int> deactivateRouteAndNotify(String routeId, {String? reason}) async {
    final res =
        await Supabase.instance.client
            .rpc(
              'driver_cancel_route',
              params: {
                'p_route': routeId,
                'p_reason': reason ?? 'Driver deactivated route manually',
              },
            )
            .select();

    if (res is List && res.isNotEmpty) {
      final map = res.first as Map<String, dynamic>;
      return (map['cancelled_count'] as int?) ?? 0;
    }
    return 0;
  }
}
