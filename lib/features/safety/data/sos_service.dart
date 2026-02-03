import 'package:supabase_flutter/supabase_flutter.dart';

class SosService {
  final SupabaseClient sb;
  SosService(this.sb);

  Future<void> triggerSOS({
    String? rideId,
    bool notifyContacts = true,
    String? customMessage, // optional override
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    // 1) Create parent alert
    final user =
        await sb.from('users').select('name').eq('id', uid).maybeSingle()
            as Map<String, dynamic>?;

    final name = (user?['name'] as String?)?.trim();
    final msg =
        customMessage ??
        '[GoDavao SOS] ${name?.isNotEmpty == true ? name : "A GoDavao user"} needs help. '
            'We’re sharing their live location with you.';

    final alertRes =
        await sb
            .from('sos_alerts')
            .insert({'user_id': uid, 'ride_id': rideId, 'message': msg})
            .select('id')
            .single();

    final alertId = (alertRes as Map)['id'] as String;

    // 2) Queue notifications to trusted contacts (SMS for now)
    if (notifyContacts) {
      final contacts = await sb
          .from('trusted_contacts')
          .select('phone, email, notify_by_sms, notify_by_email')
          .eq('user_id', uid);

      final rows = <Map<String, dynamic>>[];
      for (final c in (contacts as List)) {
        final m = Map<String, dynamic>.from(c as Map);
        final wantsSms = (m['notify_by_sms'] as bool?) ?? true;
        final phone = (m['phone'] as String?)?.trim();

        if (wantsSms && phone != null && phone.isNotEmpty) {
          rows.add({
            'alert_id': alertId,
            'recipient': _toE164(phone),
            'message': msg,
            'status': 'queued',
            'channel': 'sms',
          });
        }

        // Optionally add email rows to a separate queue/table if you implement email later
      }

      if (rows.isNotEmpty) {
        await sb.from('sos_notifications').insert(rows);
      }
    }

    // 3) Invoke the Edge Function to send queued messages
    final res = await sb.functions.invoke('send-sos', body: {});
    // Optional: check result payload
    // print('send-sos => $res');
  }

  String _toE164(String phone) {
    // minimal normalizer: ensure +63…
    final p = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('+')) return p;
    // If they entered 09xxxxxxxxx, convert to +63
    if (p.startsWith('09')) return '+63${p.substring(1)}';
    // last fallback: return raw
    return p;
  }
}
