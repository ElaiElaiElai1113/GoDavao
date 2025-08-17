import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final SupabaseClient supabase;
  AdminService(this.supabase);

  Future<bool> isCurrentUserAdmin() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final row =
        await supabase
            .from('admins')
            .select('user_id')
            .eq('user_id', uid)
            .maybeSingle();
    return row != null;
  }
}
