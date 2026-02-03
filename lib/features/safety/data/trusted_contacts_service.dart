import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/trusted_contact.dart';

class TrustedContactsService {
  final SupabaseClient _sb;
  TrustedContactsService(this._sb);

  Future<List<TrustedContact>> listMine() async {
    final uid = _sb.auth.currentUser!.id;
    final res = await _sb
        .from('trusted_contacts')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => TrustedContact.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<TrustedContact> add({
    required String name,
    required String phone,
    String? email,
  }) async {
    final res =
        await _sb
            .from('trusted_contacts')
            .insert({
              'name': name,
              'phone': phone,
              if (email != null) 'email': email,
            })
            .select()
            .single();
    return TrustedContact.fromMap(res);
  }

  Future<TrustedContact> update(
    String id, {
    required String name,
    required String phone,
    String? email,
  }) async {
    final res =
        await _sb
            .from('trusted_contacts')
            .update({'name': name, 'phone': phone, 'email': email})
            .eq('id', id)
            .select()
            .single();
    return TrustedContact.fromMap(res);
  }

  Future<void> remove(String id) async {
    await _sb.from('trusted_contacts').delete().eq('id', id);
  }
}
