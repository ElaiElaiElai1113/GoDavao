// lib/features/verify/data/verification_service.dart
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canonical verification states used in-app.
/// We map any DB string (e.g., 'approved') to these.
enum VerificationStatus { pending, verified, rejected, unknown }

VerificationStatus _parseStatus(dynamic raw) {
  final v = (raw ?? '').toString().toLowerCase().trim();
  switch (v) {
    case 'verified':
    case 'approved': // backward-compat
      return VerificationStatus.verified;
    case 'rejected':
      return VerificationStatus.rejected;
    case 'pending':
      return VerificationStatus.pending;
    default:
      return VerificationStatus.unknown;
  }
}

String _statusToText(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.verified:
      return 'verified';
    case VerificationStatus.rejected:
      return 'rejected';
    case VerificationStatus.pending:
      return 'pending';
    case VerificationStatus.unknown:
    default:
      // default to pending if unknown is being set
      return 'pending';
  }
}

class VerificationService {
  final SupabaseClient _sb;
  VerificationService(this._sb);

  // ---------- Auth/user helpers ----------
  String get _userId {
    final u = _sb.auth.currentUser;
    if (u == null) throw Exception('Not logged in');
    return u.id;
  }

  // ---------- Storage helpers ----------
  static const String _bucket = 'verifications';

  String _path(String filename) => '$_userId/$filename';

  Future<String> _uploadFile(String filename, File? file) async {
    if (file == null) return '';
    final key = _path(filename);
    await _sb.storage
        .from(_bucket)
        .upload(key, file, fileOptions: const FileOptions(upsert: true));
    return key;
  }

  String publicUrl(String key) => _sb.storage.from(_bucket).getPublicUrl(key);

  // ---------- Submit / Update request ----------
  /// Creates or updates the user's verification request.
  /// - Uploads any provided files (id/selfie/license/orcr)
  /// - Sets users.verification_status = 'pending'
  /// - Upserts into verification_requests (one row per user via onConflict: 'user_id')
  /// Creates or updates the user's verification request.
  /// - Uploads any provided files (id/selfie/license/orcr)
  /// - Sets users.verification_status = 'pending'
  /// - Upserts into verification_requests (one row per user via onConflict: 'user_id')
  Future<void> submitOrUpdate({
    required String role, // 'driver' | 'passenger'
    required String idType, // <-- NEW: e.g. "Driver’s License", "PhilSys"
    File? idFront,
    File? idBack,
    File? selfie,
    File? driverLicense,
    File? orcr,
  }) async {
    // Optional: make filenames nicer by including an idType slug.
    final typeSlug = _slug(idType); // e.g., "drivers-license", "philsys"

    // 1) Upload files only when present (avoid clobbering existing keys)
    final idFrontKey = await _uploadFile('id_${typeSlug}_front.jpg', idFront);
    final idBackKey = await _uploadFile('id_${typeSlug}_back.jpg', idBack);
    final selfieKey = await _uploadFile('selfie.jpg', selfie);
    final licenseKey =
        role == 'driver' ? await _uploadFile('license.jpg', driverLicense) : '';
    final orcrKey = role == 'driver' ? await _uploadFile('orcr.jpg', orcr) : '';

    // 2) Mark user as pending in users table (source of truth)
    await _sb
        .from('users')
        .update({
          'verification_status': 'pending',
          'verified_role': role,
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', _userId);

    // 3) Fetch existing request so we can preserve file keys that weren’t re-uploaded
    final existing =
        await _sb
            .from('verification_requests')
            .select(
              'id, id_front_key, id_back_key, selfie_key, driver_license_key, orcr_key',
            )
            .eq('user_id', _userId)
            .maybeSingle();

    String keepOr(String newKey, String? oldKey) =>
        (newKey.isNotEmpty) ? newKey : (oldKey ?? '');

    // 4) Upsert verification request row
    final payload = {
      'user_id': _userId,
      'role': role,
      'status': 'pending',
      'id_type': idType, // <-- store human-readable choice for admin filters
      'id_front_key': keepOr(idFrontKey, existing?['id_front_key']),
      'id_back_key': keepOr(idBackKey, existing?['id_back_key']),
      'selfie_key': keepOr(selfieKey, existing?['selfie_key']),
      // Only keep/require license for drivers (UI already hides if ID type is Driver’s License)
      'driver_license_key':
          role == 'driver'
              ? keepOr(licenseKey, existing?['driver_license_key'])
              : null,
      'orcr_key':
          role == 'driver' ? keepOr(orcrKey, existing?['orcr_key']) : null,
      'created_at': DateTime.now().toIso8601String(),
    };

    await _sb
        .from('verification_requests')
        .upsert(payload, onConflict: 'user_id');
  }

  // Helper: quick slug for filenames
  String _slug(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  // ---------- Status read APIs (persist across sessions) ----------
  /// Fetch the latest verification status from DB.
  /// Primary source: users.verification_status
  /// Fallback: role table (drivers/passengers) if users.verification_status is null/unknown
  Future<VerificationStatus> fetchStatus({String? userId}) async {
    final id = userId ?? _userId;

    final userRow =
        await _sb
            .from('users')
            .select('verification_status, role')
            .eq('id', id)
            .maybeSingle();

    final fromUsers = _parseStatus(userRow?['verification_status']);
    if (fromUsers != VerificationStatus.unknown) return fromUsers;

    final role = (userRow?['role'] ?? '').toString();
    if (role == 'driver') {
      final row =
          await _sb
              .from('drivers')
              .select('verification_status')
              .eq('user_id', id)
              .maybeSingle();
      return _parseStatus(row?['verification_status']);
    } else if (role == 'passenger') {
      final row =
          await _sb
              .from('passengers')
              .select('verification_status')
              .eq('user_id', id)
              .maybeSingle();
      return _parseStatus(row?['verification_status']);
    }

    return VerificationStatus.unknown;
  }

  /// Stream that emits current status immediately, then pushes realtime updates
  /// whenever users/driver/passenger verification fields change.
  // Replace your watchStatus with this version:
  Stream<VerificationStatus> watchStatus({String? userId}) async* {
    final id = userId ?? _userId;

    // 1) Emit current value first
    yield await fetchStatus(userId: id);

    // 2) Create a realtime channel and push on any relevant UPDATE
    final controller = StreamController<VerificationStatus>();

    Future<void> push() async {
      final latest = await fetchStatus(userId: id);
      if (!controller.isClosed) controller.add(latest);
    }

    final channel =
        _sb
            .channel('user-verification-$id')
            // users table updates
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'users',
              callback: (payload) {
                try {
                  final newRec = payload.newRecord ?? {};
                  if (newRec['id'] == id) push();
                } catch (_) {}
              },
            )
            // drivers table updates
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'drivers',
              callback: (payload) {
                try {
                  final newRec = payload.newRecord ?? {};
                  if (newRec['user_id'] == id) push();
                } catch (_) {}
              },
            )
            // passengers table updates
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'passengers',
              callback: (payload) {
                try {
                  final newRec = payload.newRecord ?? {};
                  if (newRec['user_id'] == id) push();
                } catch (_) {}
              },
            )
            .subscribe();

    // Kick once more to avoid UI race
    push();

    try {
      yield* controller.stream;
    } finally {
      await channel.unsubscribe();
      await controller.close();
    }
  }

  // ---------- Admin actions ----------
  /// Generic admin setter for users.verification_status, with optional linkage to a request row.
  Future<void> adminSetUserStatus({
    required String userId,
    required VerificationStatus status,
    String? requestId,
    String? notes,
  }) async {
    final statusText = _statusToText(status);

    await _sb
        .from('users')
        .update({
          'verification_status': statusText,
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);

    if (requestId != null) {
      await _sb
          .from('verification_requests')
          .update({
            'status': statusText,
            'reviewed_by': _userId,
            'reviewed_at': DateTime.now().toIso8601String(),
            if (notes != null && notes.isNotEmpty) 'notes': notes,
          })
          .eq('id', requestId);
    }
  }

  /// Backward-compatible convenience wrappers
  Future<void> approveUser(String userId, {String? requestId}) =>
      adminSetUserStatus(
        userId: userId,
        status: VerificationStatus.verified,
        requestId: requestId,
      );

  Future<void> rejectUser(String userId, {String? requestId, String? notes}) =>
      adminSetUserStatus(
        userId: userId,
        status: VerificationStatus.rejected,
        requestId: requestId,
        notes: notes,
      );
}
