// lib/features/vehicles/data/vehicles_service.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehiclesService {
  VehiclesService(this.sb);
  final SupabaseClient sb;

  // Change if your storage bucket name differs
  static const String _bucket = 'verifications';

  // Columns we routinely select (includes new or_key/cr_key + legacy orcr_key)
  static const String _vehicleCols =
      'id, driver_id, make, model, plate, color, year, seats, '
      'is_default, verification_status, created_at, '
      'submitted_at, reviewed_by, reviewed_at, review_notes, '
      'or_key, cr_key, orcr_key';

  // ---------------- Utilities ----------------

  String _requireUid() {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    return uid;
  }

  List<Map<String, dynamic>> _castList(dynamic res) {
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('Unexpected response from Supabase');
  }

  Map<String, dynamic> _castRow(dynamic row) {
    if (row == null) throw Exception('Row is null');
    if (row is Map) return Map<String, dynamic>.from(row);
    throw Exception('Unexpected row shape from Supabase');
  }

  String? _nullIfBlank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  Exception _friendlyVehicleError(PostgrestException e) {
    final msg = (e.message ?? '').toLowerCase();
    if (msg.contains('uq_vehicle_plate_per_driver')) {
      return Exception('This plate is already registered to your account.');
    }
    return Exception(e.message ?? 'Vehicle operation failed.');
  }

  // ---------------- Queries ----------------

  /// Get all vehicles for the current driver (default first).
  Future<List<Map<String, dynamic>>> listMine() async {
    final uid = _requireUid();

    final res = await sb
        .from('vehicles')
        .select(_vehicleCols)
        .eq('driver_id', uid)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return _castList(res);
  }

  /// Realtime stream of current driver's vehicles.
  Stream<List<Map<String, dynamic>>> watchMine() {
    final uid = _requireUid();
    return sb
        .from('vehicles')
        .stream(primaryKey: ['id'])
        .eq('driver_id', uid)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false)
        .map(_castList);
  }

  /// Get a specific vehicle owned by the current driver.
  Future<Map<String, dynamic>?> getVehicle(String vehicleId) async {
    final uid = _requireUid();
    final res =
        await sb
            .from('vehicles')
            .select(_vehicleCols)
            .eq('driver_id', uid)
            .eq('id', vehicleId)
            .maybeSingle();
    if (res == null) return null;
    return _castRow(res);
  }

  /// Get the current driver's default vehicle, if any.
  Future<Map<String, dynamic>?> getDefaultVehicle() async {
    final uid = _requireUid();
    final res =
        await sb
            .from('vehicles')
            .select(_vehicleCols)
            .eq('driver_id', uid)
            .eq('is_default', true)
            .maybeSingle();
    if (res == null) return null;
    return _castRow(res);
  }

  // ---------------- Create ----------------

  Future<void> createVehicle({
    required String make,
    required String model,
    String? plate,
    String? color,
    int? year,
    required int seats,
    bool isDefault = false,
  }) async {
    final uid = _requireUid();

    try {
      await sb.from('vehicles').insert({
        'driver_id': uid,
        'make': make,
        'model': model,
        'plate': _nullIfBlank(plate),
        'color': _nullIfBlank(color),
        'year': year,
        'seats': seats,
        'is_default': isDefault,
      });
    } on PostgrestException catch (e) {
      throw _friendlyVehicleError(e);
    }
  }

  // ---------------- Update ----------------

  /// Patch allowed fields on a vehicle owned by the current driver.
  Future<void> updateVehicle(
    String vehicleId,
    Map<String, dynamic> patch,
  ) async {
    final uid = _requireUid();

    final allowed = <String, dynamic>{};
    void put(String k, dynamic v) {
      if (v != null) allowed[k] = v;
    }

    put('make', patch['make']);
    put('model', patch['model']);
    put('plate', _nullIfBlank(patch['plate'] as String?));
    put('color', _nullIfBlank(patch['color'] as String?));
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
      throw _friendlyVehicleError(e);
    }
  }

  /// Convenience update when you have concrete values.
  Future<void> updateVehicleFromValues({
    required String vehicleId,
    required String make,
    required String model,
    String? plate,
    String? color,
    int? year,
    required int seats,
    bool? isDefault,
  }) {
    return updateVehicle(vehicleId, {
      'make': make,
      'model': model,
      'plate': plate,
      'color': color,
      'year': year,
      'seats': seats,
      if (isDefault != null) 'is_default': isDefault,
    });
  }

  // ---------------- Default toggle ----------------

  /// Relies on DB trigger ensure_single_default_vehicle() to keep only one default.
  Future<void> setDefault(String vehicleId) async {
    final uid = _requireUid();
    await sb
        .from('vehicles')
        .update({'is_default': true})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  // ---------------- Delete ----------------

  Future<void> deleteVehicle(String vehicleId) async {
    final uid = _requireUid();
    await sb.from('vehicles').delete().eq('id', vehicleId).eq('driver_id', uid);
  }

  // ---------------- Documents: OR & CR (separate) ----------------

  /// Upload OR image/PDF to storage and store `or_key` on the vehicle.
  Future<void> uploadOR({required String vehicleId, required File file}) async {
    final uid = _requireUid();

    final ext = file.path.split('.').last.toLowerCase();
    final key =
        'or/$uid/$vehicleId-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await sb.storage.from(_bucket).upload(key, file);
    await sb
        .from('vehicles')
        .update({'or_key': key})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  /// Upload CR image/PDF to storage and store `cr_key` on the vehicle.
  Future<void> uploadCR({required String vehicleId, required File file}) async {
    final uid = _requireUid();

    final ext = file.path.split('.').last.toLowerCase();
    final key =
        'cr/$uid/$vehicleId-${DateTime.now().millisecondsSinceEpoch}.$ext';

    await sb.storage.from(_bucket).upload(key, file);
    await sb
        .from('vehicles')
        .update({'cr_key': key})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  /// Remove OR file and clear `or_key`.
  Future<void> removeOR(String vehicleId) async {
    final uid = _requireUid();
    final v = await getVehicle(vehicleId);
    final key = (v?['or_key'] as String?) ?? '';
    if (key.isNotEmpty) {
      try {
        await sb.storage.from(_bucket).remove([key]);
      } catch (_) {
        // non-fatal
      }
    }
    await sb
        .from('vehicles')
        .update({'or_key': null})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  /// Remove CR file and clear `cr_key`.
  Future<void> removeCR(String vehicleId) async {
    final uid = _requireUid();
    final v = await getVehicle(vehicleId);
    final key = (v?['cr_key'] as String?) ?? '';
    if (key.isNotEmpty) {
      try {
        await sb.storage.from(_bucket).remove([key]);
      } catch (_) {
        // non-fatal
      }
    }
    await sb
        .from('vehicles')
        .update({'cr_key': null})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  /// Get a short-lived signed URL to preview a document (OR or CR).
  Future<String?> signedUrl(String? storageKey, {int expiresIn = 300}) async {
    if (storageKey == null || storageKey.isEmpty) return null;
    return await sb.storage
        .from(_bucket)
        .createSignedUrl(storageKey, expiresIn);
  }

  // ---------------- Submit / Resubmit ----------------

  /// Submit for verification. Requires BOTH OR and CR present.
  /// (Backwards compatible: if `or_key`/`cr_key` missing but legacy `orcr_key`
  /// exists, you may relax this check — current implementation requires both).
  Future<void> submitForVerificationBoth(String vehicleId) async {
    final uid = _requireUid();

    final v =
        await sb
            .from('vehicles')
            .select('or_key, cr_key, orcr_key')
            .eq('id', vehicleId)
            .eq('driver_id', uid)
            .maybeSingle();

    final orKey = (v?['or_key'] as String?) ?? '';
    final crKey = (v?['cr_key'] as String?) ?? '';
    final legacy = (v?['orcr_key'] as String?) ?? '';

    // Require both new fields; if you want to allow legacy, relax this.
    if (orKey.isEmpty || crKey.isEmpty) {
      // If you want to accept legacy ORCR instead, uncomment next 3 lines:
      // if (legacy.isNotEmpty) {
      //   // allow submit with legacy single-file upload
      // } else
      throw Exception(
        'Please upload both OR and CR documents before submitting.',
      );
    }

    await sb
        .from('vehicles')
        .update({
          'verification_status': 'pending',
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by': null,
          'reviewed_at': null,
          'review_notes': null,
        })
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  /// Alias for resubmission after rejection (same flow).
  Future<void> resubmitBoth(String vehicleId) =>
      submitForVerificationBoth(vehicleId);
}
