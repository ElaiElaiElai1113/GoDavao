import 'package:supabase_flutter/supabase_flutter.dart';
import 'vehicle.dart';

class VehicleService {
  final SupabaseClient sb;
  VehicleService(this.sb);

  String? get _uid => sb.auth.currentUser?.id;

  Future<List<Vehicle>> listMyVehicles() async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await sb
        .from('vehicles')
        .select('*')
        .eq('driver_id', uid)
        .order('is_primary', ascending: false)
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => Vehicle.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Vehicle> createVehicle({
    required String plate,
    required String make,
    required String model,
    String? color,
    int? year,
    int? seats,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    final insert = {
      'driver_id': uid,
      'plate': plate.trim(),
      'make': make.trim(),
      'model': model.trim(),
      if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
      if (year != null) 'year': year,
      if (seats != null) 'seats': seats,
    };
    final res = await sb.from('vehicles').insert(insert).select().single();
    return Vehicle.fromMap(res as Map<String, dynamic>);
  }

  Future<Vehicle> updateVehicle(String id, Vehicle updated) async {
    final res =
        await sb
            .from('vehicles')
            .update(updated.toUpdate())
            .eq('id', id)
            .select()
            .single();
    return Vehicle.fromMap(res as Map<String, dynamic>);
  }

  Future<void> deleteVehicle(String id) async {
    await sb.from('vehicles').delete().eq('id', id);
  }

  /// Sets this vehicle as primary, and clears others for this driver.
  Future<void> setPrimary(String id) async {
    final uid = _uid;
    if (uid == null) return;
    final rpcSupported = false; // flip to true if you add a Postgres function
    if (rpcSupported) {
      // await sb.rpc('set_primary_vehicle', params: {'p_vehicle_id': id});
      return;
    }
    final _ = await sb
        .from('vehicles')
        .update({'is_primary': false})
        .eq('driver_id', uid);
    await sb.from('vehicles').update({'is_primary': true}).eq('id', id);
  }
}
