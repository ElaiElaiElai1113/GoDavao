import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentService {
  final SupabaseClient supabase;
  PaymentService(this.supabase);

  Future<Map<String, dynamic>?> getPaymentForRide(String rideId) async {
    final row =
        await supabase
            .from('payments')
            .select()
            .eq('ride_id', rideId)
            .maybeSingle();
    return (row as Map?)?.cast<String, dynamic>();
  }

  Future<String> _uploadProof(String localPath) async {
    final uid = supabase.auth.currentUser!.id;
    final ext = p.extension(localPath);
    final object = '$uid/${DateTime.now().millisecondsSinceEpoch}$ext';
    final file = File(localPath);
    final mime = lookupMimeType(localPath) ?? 'application/octet-stream';

    await supabase.storage
        .from('gcash_proofs')
        .upload(
          object,
          file,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    return object; // store object key
  }

  Future<void> submitGcashProof({
    required String rideId,
    required String refNo,
    required double amount,
    required String localImagePath,
    String? note,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    final object = await _uploadProof(localImagePath);

    // Upsert one payment per ride
    await supabase.from('payments').upsert({
      'ride_id': rideId,
      'passenger_id': uid,
      'method': 'gcash',
      'amount': amount,
      'status': 'pending',
      'ref_no': refNo,
      'proof_object': object,
      'note': note,
    }, onConflict: 'ride_id');
  }

  String publicUrl(String object) {
    // admins will view via signed url, but for MVP just use createSignedUrl if needed
    return supabase.storage.from('gcash_proofs').getPublicUrl(object);
  }

  Future<String> signedUrl(String object, {int expiresInSec = 3600}) async {
    final res = await supabase.storage
        .from('gcash_proofs')
        .createSignedUrl(object, expiresInSec);
    return res;
  }
}
