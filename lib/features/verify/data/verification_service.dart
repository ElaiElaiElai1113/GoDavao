import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  final SupabaseClient supabase;
  VerificationService(this.supabase);

  Future<String> _upload(String localPath, {required String prefix}) async {
    final uid = supabase.auth.currentUser!.id;
    final ext = p.extension(localPath);
    final object = '$uid/$prefix-${DateTime.now().millisecondsSinceEpoch}$ext';

    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('File not found: $localPath');
    }

    final mime = lookupMimeType(localPath) ?? 'application/octet-stream';

    // If an object with the same name could exist from retries, set upsert:true.
    await supabase.storage
        .from('id_docs')
        .upload(
          object,
          file,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    return object;
  }

  Future<void> submitRequest({
    required String selfiePath,
    required String idFrontPath,
    String? idBackPath,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    final selfieKey = await _upload(selfiePath, prefix: 'selfie');
    final frontKey = await _upload(idFrontPath, prefix: 'id-front');
    String? backKey;
    if (idBackPath != null)
      backKey = await _upload(idBackPath, prefix: 'id-back');

    await supabase.from('verification_requests').insert({
      'user_id': uid,
      'selfie_url': selfieKey,
      'id_front_url': frontKey,
      'id_back_url': backKey,
      'status': 'pending',
    });
  }

  Future<Map<String, dynamic>?> myLatest() async {
    final uid = supabase.auth.currentUser!.id;
    final row =
        await supabase
            .from('verification_requests')
            .select(
              'id,status,reason,created_at,selfie_url,id_front_url,id_back_url',
            )
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row as Map);
  }

  // Signed URL for private file
  Future<String> signUrl(String key, {int expiresInSeconds = 3600}) async {
    final res = await supabase.storage
        .from('id_docs')
        .createSignedUrl(key, expiresInSeconds);
    return res;
  }

  // Admin
  Future<List<Map<String, dynamic>>> adminListPending() async {
    final rows = await supabase
        .from('verification_requests')
        .select(
          'id,user_id,created_at,selfie_url,id_front_url,id_back_url,status,reason',
        )
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> adminSetStatus({
    required String requestId,
    required String status, // 'approved' | 'rejected'
    String? reason,
  }) async {
    await supabase
        .from('verification_requests')
        .update({
          'status': status,
          'reason': reason,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          'reviewed_by': supabase.auth.currentUser!.id,
        })
        .eq('id', requestId);
    // trigger flips profiles.verified via trigger
  }

  Future<bool> isVerified(String userId) async {
    final row =
        await supabase
            .from('users')
            .select('verified')
            .eq('id', userId)
            .maybeSingle();
    return (row != null) && ((row as Map)['verified'] == true);
  }
}
