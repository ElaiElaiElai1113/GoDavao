// lib/features/vehicles/data/vehicles_service.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class VehiclesService {
  final SupabaseClient sb;
  VehiclesService(this.sb);

  // Storage
  static const String _bucket = 'verifications';

  // Columns your UI expects
  static const String _vehicleCols =
      'id, driver_id, make, model, plate, color, year, seats, '
      'is_default, verification_status, created_at, '
      'submitted_at, reviewed_by, reviewed_at, review_notes, '
      'or_key, cr_key, orcr_key, or_number, cr_number';

  /* ──────────────────────────── Utilities ─────────────────────────── */

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

  String _nowUtcIso() => DateTime.now().toUtc().toIso8601String();

  /* ──────────────────────────── Queries ───────────────────────────── */

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

  Future<Map<String, dynamic>?> getVehicle(String vehicleId) async {
    final uid = _requireUid();
    final res =
        await sb
            .from('vehicles')
            .select(_vehicleCols)
            .eq('driver_id', uid)
            .eq('id', vehicleId)
            .maybeSingle();
    return res == null ? null : _castRow(res);
  }

  Future<Map<String, dynamic>?> getDefaultVehicle() async {
    final uid = _requireUid();
    final res =
        await sb
            .from('vehicles')
            .select(_vehicleCols)
            .eq('driver_id', uid)
            .eq('is_default', true)
            .maybeSingle();
    return res == null ? null : _castRow(res);
  }

  /* ─────────────────────────── Create/Update ──────────────────────── */

  /// Create vehicle. Always creates as non-default.
  /// If user has no default yet, we set this one as default afterward.
  Future<String> createVehicle({
    required String make,
    required String model,
    String? plate,
    String? color,
    int? year,
    required int seats,
    String? orNumber,
    String? crNumber,
  }) async {
    final uid = _requireUid();

    try {
      // check if user already has a default
      final currentDefault = await getDefaultVehicle();

      // insert as non-default
      final inserted =
          await sb
              .from('vehicles')
              .insert({
                'driver_id': uid,
                'make': make,
                'model': model,
                'plate': _nullIfBlank(plate),
                'color': _nullIfBlank(color),
                'year': year,
                'seats': seats,
                'is_default': false,
                if (_nullIfBlank(orNumber) != null)
                  'or_number': _nullIfBlank(orNumber),
                if (_nullIfBlank(crNumber) != null)
                  'cr_number': _nullIfBlank(crNumber),
              })
              .select('id')
              .single();

      final id = (inserted['id'] as String?) ?? '';
      if (id.isEmpty) {
        throw Exception('Vehicle created but id not returned.');
      }

      // if user has no default yet, make this one default
      if (currentDefault == null) {
        await setDefault(id);
      }

      return id;
    } on PostgrestException catch (e) {
      throw _friendlyVehicleError(e);
    }
  }

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
    // we don’t let callers arbitrarily set is_default here
    if (patch.containsKey('or_number') || patch.containsKey('orNumber')) {
      put('or_number', _nullIfBlank((patch['or_number'] ?? patch['orNumber']) as String?));
    }
    if (patch.containsKey('cr_number') || patch.containsKey('crNumber')) {
      put('cr_number', _nullIfBlank((patch['cr_number'] ?? patch['crNumber']) as String?));
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

  Future<void> updateVehicleFromValues({
    required String vehicleId,
    required String make,
    required String model,
    String? plate,
    String? color,
    int? year,
    required int seats,
    String? orNumber,
    String? crNumber,
  }) {
    return updateVehicle(vehicleId, {
      'make': make,
      'model': model,
      'plate': plate,
      'color': color,
      'year': year,
      'seats': seats,
      if (orNumber != null) 'or_number': orNumber,
      if (crNumber != null) 'cr_number': crNumber,
    });
  }

  /* ───────────────────────── Default toggle ───────────────────────── */

  /// Make exactly one vehicle default for this driver.
  /// 1) unset current default for driver
  /// 2) set the given vehicle as default
  Future<void> setDefault(String vehicleId) async {
    final uid = _requireUid();

    // 1) unset current default (if any)
    await sb
        .from('vehicles')
        .update({'is_default': false})
        .eq('driver_id', uid)
        .eq('is_default', true);

    // 2) set the chosen one
    final res =
        await sb
            .from('vehicles')
            .update({'is_default': true})
            .eq('driver_id', uid)
            .eq('id', vehicleId)
            .select('id')
            .maybeSingle();

    if (res == null) {
      throw Exception('Vehicle not found or not owned by user.');
    }
  }

  /* ─────────────────────────── Delete ────────────────────────────── */

  Future<void> deleteVehicle(String vehicleId) async {
    final uid = _requireUid();

    // Clean up storage keys first (best effort)
    try {
      final v = await getVehicle(vehicleId);
      final keys = <String>[];
      final orKey = v?['or_key'] as String?;
      final crKey = v?['cr_key'] as String?;
      final legacy = v?['orcr_key'] as String?;
      if (orKey != null && orKey.isNotEmpty) keys.add(orKey);
      if (crKey != null && crKey.isNotEmpty) keys.add(crKey);
      if (legacy != null && legacy.isNotEmpty) keys.add(legacy);
      if (keys.isNotEmpty) {
        await sb.storage.from(_bucket).remove(keys);
      }
    } catch (_) {
      // ignore storage errors on delete
    }

    await sb.from('vehicles').delete().eq('id', vehicleId).eq('driver_id', uid);
  }

  /* ─────────────────────── Document Uploads ──────────────────────── */

  Future<void> uploadOR({required String vehicleId, required File file}) async {
    final uid = _requireUid();
    final ext = file.path.split('.').last.toLowerCase();
    final fileName = 'or_${const Uuid().v4()}.$ext';
    final key = '$uid/$vehicleId/$fileName';

    await sb.storage
        .from(_bucket)
        .upload(key, file, fileOptions: const FileOptions(upsert: true));

    await sb
        .from('vehicles')
        .update({
          'or_key': key,
          'verification_status': 'pending',
          'submitted_at': _nowUtcIso(),
          'reviewed_by': null,
          'reviewed_at': null,
          'review_notes': null,
        })
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  Future<void> uploadCR({required String vehicleId, required File file}) async {
    final uid = _requireUid();
    final ext = file.path.split('.').last.toLowerCase();
    final fileName = 'cr_${const Uuid().v4()}.$ext';
    final key = '$uid/$vehicleId/$fileName';

    await sb.storage
        .from(_bucket)
        .upload(key, file, fileOptions: const FileOptions(upsert: true));

    await sb
        .from('vehicles')
        .update({
          'cr_key': key,
          'verification_status': 'pending',
          'submitted_at': _nowUtcIso(),
          'reviewed_by': null,
          'reviewed_at': null,
          'review_notes': null,
        })
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  Future<void> removeOR(String vehicleId) async {
    final uid = _requireUid();
    final v = await getVehicle(vehicleId);
    final key = v?['or_key'] as String?;
    if (key != null && key.isNotEmpty) {
      await sb.storage.from(_bucket).remove([key]);
    }
    await sb
        .from('vehicles')
        .update({'or_key': null})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  Future<void> removeCR(String vehicleId) async {
    final uid = _requireUid();
    final v = await getVehicle(vehicleId);
    final key = v?['cr_key'] as String?;
    if (key != null && key.isNotEmpty) {
      await sb.storage.from(_bucket).remove([key]);
    }
    await sb
        .from('vehicles')
        .update({'cr_key': null})
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  Future<String?> signedUrl(String? storageKey, {int expiresIn = 300}) async {
    if (storageKey == null || storageKey.isEmpty) return null;
    final res = await sb.storage
        .from(_bucket)
        .createSignedUrl(storageKey, expiresIn);
    return res;
  }

  /* ───────────────────────── Verification ───────────────────────── */

  Future<void> submitForVerificationBoth(String vehicleId) async {
    final uid = _requireUid();
    final v =
        await sb
            .from('vehicles')
            .select('or_key, cr_key, orcr_key')
            .eq('id', vehicleId)
            .eq('driver_id', uid)
            .maybeSingle();

    final orKey = v?['or_key'] as String? ?? '';
    final crKey = v?['cr_key'] as String? ?? '';
    final legacy = v?['orcr_key'] as String? ?? '';

    if (orKey.isEmpty || crKey.isEmpty) {
      if (legacy.isEmpty) {
        throw Exception(
          'Please upload both OR and CR documents before submitting.',
        );
      }
    }

    await sb
        .from('vehicles')
        .update({
          'verification_status': 'pending',
          'submitted_at': _nowUtcIso(),
          'reviewed_by': null,
          'reviewed_at': null,
          'review_notes': null,
        })
        .eq('id', vehicleId)
        .eq('driver_id', uid);
  }

  Future<void> resubmitBoth(String vehicleId) =>
      submitForVerificationBoth(vehicleId);
}
