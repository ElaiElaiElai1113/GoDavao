// lib/features/verify/data/verification_service.dart
import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canonical, app-level verification states.
/// (We normalize any DB string to one of these.)
enum VerificationStatus { pending, verified, rejected, unknown }

/// Parse arbitrary DB value into a canonical [VerificationStatus].
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

/// Convert canonical status back into a DB string.
String _statusToText(VerificationStatus s) {
  switch (s) {
    case VerificationStatus.verified:
      return 'approved';
    case VerificationStatus.rejected:
      return 'rejected';
    case VerificationStatus.pending:
      return 'pending';
    case VerificationStatus.unknown:
      // If someone attempts to set unknown, treat it as pending.
      return 'pending';
  }
}

class VerificationService {
  VerificationService(this._sb);

  final SupabaseClient _sb;

  // ------------------------- Auth helpers -------------------------

  /// Current authenticated user id or throws if not logged in.
  String get _userId {
    final u = _sb.auth.currentUser;
    if (u == null) {
      throw StateError('Not logged in');
    }
    return u.id;
  }

  // ------------------------- Storage helpers -------------------------

  /// Storage bucket for verification artifacts.
  static const String _bucket = 'verifications';

  /// Compose a stable, per-user path for a file inside [_bucket].
  String _path(String filename) => '$_userId/$filename';

  /// Upload [file] to storage (if provided) with upsert behavior.
  /// Returns the object key (path) or empty string if no file.
  Future<String> _uploadFile(String filename, File? file) async {
    if (file == null) return '';
    final key = _path(filename);
    await _sb.storage
        .from(_bucket)
        .upload(key, file, fileOptions: const FileOptions(upsert: true));
    return key;
  }

  /// Public URL (works if bucket/object is public).
  String publicUrl(String key) => _sb.storage.from(_bucket).getPublicUrl(key);

  /// Signed URL for private buckets with fallback to public.
  Future<String> signedOrPublicUrl(
    String key, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
    if (key.isEmpty) return '';
    try {
      final signed = await _sb.storage
          .from(_bucket)
          .createSignedUrl(key, ttl.inSeconds);
      return signed;
    } catch (_) {
      // If bucket/object is public (or signing not available), fall back.
      return publicUrl(key);
    }
  }

  // ------------------------- Submit / Update -------------------------

  /// Create or update the caller's verification request.
  ///
  /// Behavior:
  /// - Uploads any provided files without clobbering missing ones.
  /// - Sets `users.verification_status = 'pending'`, `verified_role`, `verified_at`.
  /// - Upserts into `verification_requests` keyed by `user_id`.
  ///
  /// Arguments:
  /// - [role]: 'driver' | 'passenger'
  /// - [idType]: human readable doc type (e.g. "Driver’s License", "PhilSys")
  Future<void> submitOrUpdate({
    required String role,
    required String idType,
    File? idFront,
    File? idBack,
    File? selfie,
    File? driverLicense,
    File? orcr,
  }) async {
    // Normalize role a bit (non-fatal safeguard).
    final roleNorm = (role).toLowerCase().trim();
    if (roleNorm != 'driver' && roleNorm != 'passenger') {
      throw ArgumentError.value(
        role,
        'role',
        "Must be 'driver' or 'passenger'",
      );
    }

    // Nicer filenames — stable and explicit.
    final typeSlug = _slug(idType);

    // 1) Upload only the files that were provided.
    final idFrontKey = await _uploadFile('id_${typeSlug}_front.jpg', idFront);
    final idBackKey = await _uploadFile('id_${typeSlug}_back.jpg', idBack);
    final selfieKey = await _uploadFile('selfie.jpg', selfie);
    final licenseKey =
        roleNorm == 'driver'
            ? await _uploadFile('license.jpg', driverLicense)
            : '';
    final orcrKey =
        roleNorm == 'driver' ? await _uploadFile('orcr.jpg', orcr) : '';

    // 2) Mark user as pending in `users` (source of truth).
    await _sb
    .from('users')
    .update({
      'verification_status': 'pending',
      'verified_role': roleNorm,
      'verified_at': null, // ← only set on approval
    })
    .eq('id', _userId);

    // 3) Fetch existing request so we can preserve file keys if not re-uploaded.
    final existing =
        await _sb
            .from('verification_requests')
            .select(
              'id, id_front_key, id_back_key, selfie_key, driver_license_key, orcr_key',
            )
            .eq('user_id', _userId)
            .maybeSingle();

    String keepOr(String newKey, String? oldKey) =>
        newKey.isNotEmpty ? newKey : (oldKey ?? '');

    // 4) Upsert request row.
    final payload = <String, dynamic>{
      'user_id': _userId,
      'role': roleNorm,
      'status': 'pending',
      'id_type': idType, // keep the human-readable value for admin filters
      'id_front_key': keepOr(idFrontKey, existing?['id_front_key'] as String?),
      'id_back_key': keepOr(idBackKey, existing?['id_back_key'] as String?),
      'selfie_key': keepOr(selfieKey, existing?['selfie_key'] as String?),
      'driver_license_key':
          roleNorm == 'driver'
              ? keepOr(licenseKey, existing?['driver_license_key'] as String?)
              : null,
      'orcr_key':
          roleNorm == 'driver' ? keepOr(orcrKey, existing?['orcr_key'] as String?) : null,
      'created_at': DateTime.now().toIso8601String(),
    };

    await _sb
        .from('verification_requests')
        .upsert(payload, onConflict: 'user_id');
  }

  /// Quick slug for filenames.
  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  // ------------------------- Status read APIs -------------------------

  /// Fetch the latest status for [userId] (or current user).
  /// Priority:
  /// 1) users.verification_status
  /// 2) drivers/passengers.verification_status (fallback)
  Future<VerificationStatus> fetchStatus({String? userId}) async {
    final id = userId ?? _userId;

    final userRow =
        await _sb
            .from('users')
            .select('verification_status, role')
            .eq('id', id)
            .maybeSingle();

    final primary = _parseStatus(userRow?['verification_status']);
    if (primary != VerificationStatus.unknown) return primary;

    final role = (userRow?['role'] ?? '').toString();
    if (role == 'driver') {
      final row =
          await _sb
              .from('drivers')
              .select('verification_status')
              .eq('user_id', id)
              .maybeSingle();
      return _parseStatus(row?['verification_status']);
    }
    if (role == 'passenger') {
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

  /// Emit current status immediately, then push updates when
  /// any relevant table changes (users/drivers/passengers).
  Stream<VerificationStatus> watchStatus({String? userId}) async* {
    final id = userId ?? _userId;

    // 1) Emit current immediately.
    yield await fetchStatus(userId: id);

    // 2) Listen to DB changes and push refreshed value.
    final controller = StreamController<VerificationStatus>();

    Future<void> _push() async {
      try {
        final latest = await fetchStatus(userId: id);
        if (!controller.isClosed) controller.add(latest);
      } catch (_) {
        // Swallow; we don't want to break the stream on transient issues.
      }
    }

    final channel =
        _sb
            .channel('user-verification-$id')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'users',
              callback: (payload) {
                final newRec = payload.newRecord;
                if (newRec['id'] == id) _push();
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'drivers',
              callback: (payload) {
                final newRec = payload.newRecord;
                if (newRec['user_id'] == id) _push();
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'passengers',
              callback: (payload) {
                final newRec = payload.newRecord;
                if (newRec['user_id'] == id) _push();
              },
            )
            .subscribe();

    // Nudge once more after subscription to mitigate race conditions.
    _push();

    try {
      yield* controller.stream;
    } finally {
      await channel.unsubscribe();
      await controller.close();
    }
  }

  // ------------------------- Admin actions -------------------------

  /// Set a user's verification status (and optionally link to a request).
  Future<void> adminSetUserStatus({
    required String userId,
    required VerificationStatus status,
    String? requestId,
    String? notes,
  }) async {
    final statusText = _statusToText(status);

    // 1) Update the user record (source of truth in the app).
    await _sb.from('users').update({
  'verification_status': statusText,
  'verified_at': status == VerificationStatus.verified
      ? DateTime.now().toIso8601String()
      : null,
}).eq('id', userId);

    // 2) Optionally annotate the latest verification request.
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

  /// Convenience wrapper for approve.
  Future<void> approveUser(String userId, {String? requestId}) =>
      adminSetUserStatus(
        userId: userId,
        status: VerificationStatus.verified,
        requestId: requestId,
      );

  /// Convenience wrapper for reject (with optional notes).
  Future<void> rejectUser(String userId, {String? requestId, String? notes}) =>
      adminSetUserStatus(
        userId: userId,
        status: VerificationStatus.rejected,
        requestId: requestId,
        notes: notes,
      );
}
