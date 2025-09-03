// lib/features/verify/data/verification_service.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  final SupabaseClient _sb;
  VerificationService(this._sb);

  String get _userId {
    final u = _sb.auth.currentUser;
    if (u == null) throw Exception('Not logged in');
    return u.id;
  }

  String _path(String filename) => '$_userId/$filename';

  Future<String> _uploadFile(String filename, File? file) async {
    if (file == null) return '';
    final key = _path(filename);
    await _sb.storage
        .from('verifications')
        .upload(key, file, fileOptions: const FileOptions(upsert: true));
    return key;
  }

  Future<void> submitOrUpdate({
    required String role,
    File? idFront,
    File? idBack,
    File? selfie,
    File? driverLicense,
    File? orcr,
  }) async {
    // 1) Upload any provided files
    final idFrontKey = await _uploadFile('id_front.jpg', idFront);
    final idBackKey = await _uploadFile('id_back.jpg', idBack);
    final selfieKey = await _uploadFile('selfie.jpg', selfie);
    final licenseKey =
        role == 'driver' ? await _uploadFile('license.jpg', driverLicense) : '';
    final orcrKey = role == 'driver' ? await _uploadFile('orcr.jpg', orcr) : '';

    // 2) Mark user as pending
    await _sb
        .from('users')
        .update({
          'verification_status': 'pending',
          'verified_role': role,
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', _userId);

    // 3) Upsert verification request row (one active row per user is typical)
    // If you want to allow multiple attempts, use insert() instead.
    await _sb.from('verification_requests').upsert({
      'user_id': _userId,
      'role': role,
      'status': 'pending',
      'id_front_key': idFrontKey.isEmpty ? null : idFrontKey,
      'id_back_key': idBackKey.isEmpty ? null : idBackKey,
      'selfie_key': selfieKey.isEmpty ? null : selfieKey,
      'driver_license_key': licenseKey.isEmpty ? null : licenseKey,
      'orcr_key': orcrKey.isEmpty ? null : orcrKey,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id'); // ensures one row per user
  }

  Future<void> approveUser(String userId, {String? requestId}) async {
    await _sb
        .from('users')
        .update({
          'verification_status': 'approved',
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);

    if (requestId != null) {
      await _sb
          .from('verification_requests')
          .update({
            'status': 'approved',
            'reviewed_by': _userId,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId);
    }
  }

  Future<void> rejectUser(
    String userId, {
    String? requestId,
    String? notes,
  }) async {
    await _sb
        .from('users')
        .update({
          'verification_status': 'rejected',
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);

    if (requestId != null) {
      await _sb
          .from('verification_requests')
          .update({
            'status': 'rejected',
            'reviewed_by': _userId,
            'reviewed_at': DateTime.now().toIso8601String(),
            if (notes != null && notes.isNotEmpty) 'notes': notes,
          })
          .eq('id', requestId);
    }
  }

  String publicUrl(String key) =>
      _sb.storage.from('verifications').getPublicUrl(key);
}
