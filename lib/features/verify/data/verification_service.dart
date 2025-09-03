import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  final SupabaseClient _sb;

  VerificationService(this._sb);

  /// Get current user ID
  String get _userId {
    final u = _sb.auth.currentUser;
    if (u == null) {
      throw Exception('Not logged in');
    }
    return u.id;
  }

  /// Build storage path like "userId/filename"
  String _path(String filename) => '$_userId/$filename';

  /// Upload file to Supabase Storage (skip if null)
  Future<String> _uploadFile(String filename, File? file) async {
    if (file == null) return '';
    final key = _path(filename);
    await _sb.storage
        .from('verifications')
        .upload(key, file, fileOptions: const FileOptions(upsert: true));
    return key;
  }

  /// Submit or update verification request
  Future<void> submitOrUpdate({
    required String role,
    File? idFront,
    File? idBack,
    File? selfie,
    File? driverLicense,
    File? orcr,
  }) async {
    // Upload provided docs
    await _uploadFile('id_front.jpg', idFront);
    await _uploadFile('id_back.jpg', idBack);
    await _uploadFile('selfie.jpg', selfie);

    if (role == 'driver') {
      await _uploadFile('license.jpg', driverLicense);
      await _uploadFile('orcr.jpg', orcr);
    }

    // Update users table (set to pending review)
    await _sb
        .from('users')
        .update({
          'verification_status': 'pending',
          'verified_role': role,
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', _userId);
  }

  /// Mark user as approved (admin side)
  Future<void> approveUser(String userId) async {
    await _sb
        .from('users')
        .update({
          'verification_status': 'approved',
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  /// Mark user as rejected (admin side)
  Future<void> rejectUser(String userId) async {
    await _sb
        .from('users')
        .update({
          'verification_status': 'rejected',
          'verified_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  /// Get a public URL for preview/download
  String publicUrl(String key) {
    return _sb.storage.from('verifications').getPublicUrl(key);
  }
}
