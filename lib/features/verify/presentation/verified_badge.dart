// lib/features/verify/presentation/verified_badge.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerifiedBadge extends StatelessWidget {
  final String userId;
  final double size;

  const VerifiedBadge({super.key, required this.userId, this.size = 20});

  Future<String?> _fetchStatus(String uid) async {
    final supabase = Supabase.instance.client;
    final row =
        await supabase
            .from('users')
            .select('verification_status')
            .eq('id', uid)
            .maybeSingle();
    return row?['verification_status'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fetchStatus(userId),
      builder: (ctx, snap) {
        final status = snap.data;
        if (status == 'approved') {
          return Icon(Icons.verified, color: Colors.green, size: size);
        }
        if (status == 'pending') {
          return Icon(Icons.hourglass_bottom, color: Colors.orange, size: size);
        }
        return const SizedBox.shrink(); // nothing if not verified
      },
    );
  }
}
