import 'package:supabase_flutter/supabase_flutter.dart';

class VehiclesService {
  final SupabaseClient sb;
  VehiclesService(this.sb);

  // ---------------- Queries ----------------

  Future<List<Map<String, dynamic>>> listMine() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final res = await sb
        .from('vehicles')
        .select(
          'id, make, model, plate, color, year, seats, is_default, verification_status, created_at',
        )
        .eq('driver_id', uid)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return (res as List).map((e) => (e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>?> getVehicle(String vehicleId) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final res =
        await sb
            .from('vehicles')
            .select(
              'id, make, model, plate, color, year, seats, is_default, verification_status, created_at',
            )
            .eq('driver_id', uid)
            .eq('id', vehicleId)
            .maybeSingle();

    if (res == null) return null;
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>?> getDefaultVehicle() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final res =
        await sb
            .from('vehicles')
            .select(
              'id, make, model, plate, color, year, seats, is_default, verification_status, created_at',
            )
            .eq('driver_id', uid)
            .eq('is_default', true)
            .maybeSingle();

    if (res == null) return null;
    return Map<String, dynamic>.from(res as Map);
  }

  // ---------------- Create ----------------

  /// Your existing name
  Future<void> addVehicle({
    required String make,
    required String model,
    String? plate,
    String? color,
    int? year,
    required int seats,
    bool isDefault = false,
  }) async {
    await createVehicle(
      make: make,
      model: model,
      plate: plate,
      color: color,
      year: year,
      seats: seats,
      isDefault: isDefault,
    );
  }

  /// Name expected by VehicleFormPage
  Future<void> createVehicle({
    required String make,
    required String model,
    String? plate,
    String? color,
    int? year,
    required int seats,
    bool isDefault = false,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    try {
      await sb.from('vehicles').insert({
        'driver_id': uid,
        'make': make,
        'model': model,
        'plate': (plate?.trim().isEmpty ?? true) ? null : plate!.trim(),
        'color': (color?.trim().isEmpty ?? true) ? null : color!.trim(),
        'year': year,
        'seats': seats,
        'is_default': isDefault,
      });
    } on PostgrestException catch (e) {
      // nicer duplicate-plate message
      if ((e.message ?? '').toLowerCase().contains(
        'uq_vehicle_plate_per_driver',
      )) {
        throw Exception('This plate is already registered to your account.');
      }
      rethrow;
    }
  }

  // ---------------- Update ----------------

  /// Name expected by VehicleFormPage
  Future<void> updateVehicle(
    String vehicleId,
    Map<String, dynamic> patch,
  ) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    // Clean the patch to allowed columns only
    final allowed = <String, dynamic>{};
    void put(String key, dynamic value) {
      if (value != null) allowed[key] = value;
    }

    put('make', patch['make']);
    put('model', patch['model']);
    put(
      'plate',
      (patch['plate'] is String && (patch['plate'] as String).trim().isEmpty)
          ? null
          : patch['plate'],
    );
    put(
      'color',
      (patch['color'] is String && (patch['color'] as String).trim().isEmpty)
          ? null
          : patch['color'],
    );
    put('year', patch['year']);
    put('seats', patch['seats']);
    if (patch.containsKey('is_default')) {
      put('is_default', patch['is_default']);
    }

    if (allowed.isEmpty) return;

    try {
      await sb
          .from('vehicles')
          .update(allowed)
          .eq('id', vehicleId)
          .eq('driver_id', uid);
    } on PostgrestException catch (e) {
      if ((e.message ?? '').toLowerCase().contains(
        'uq_vehicle_plate_per_driver',
      )) {
        throw Exception('This plate is already registered to your account.');
      }
      rethrow;
    }
  }

  /// Overload to accept your Vehicle model if you prefer:
  /// VehiclesService.updateVehicle(vehicle.id, vehicle.toMapForUpdate());
  Future<void> updateVehicleFromModel(
    String vehicleId,
    String make,
    String model,
    String? plate,
    String? color,
    int? year,
    int seats, {
    bool? isDefault,
  }) => updateVehicle(vehicleId, {
    'make': make,
    'model': model,
    'plate': plate,
    'color': color,
    'year': year,
    'seats': seats,
    if (isDefault != null) 'is_default': isDefault,
  });

  // ---------------- Default toggle ----------------

  Future<void> setDefault(String vehicleId) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    // rely on DB trigger ensure_single_default_vehicle()
    await sb
        .from('vehicles')
        .update({'is_default': true})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  // ---------------- Delete ----------------

  Future<void> deleteVehicle(String vehicleId) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    await sb.from('vehicles').delete().eq('id', vehicleId).eq('driver_id', uid);
  }
}
