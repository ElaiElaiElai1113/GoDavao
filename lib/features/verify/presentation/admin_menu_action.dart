import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/verify/data/admin_service.dart';
import 'package:godavao/features/verify/presentation/admin_verification_page.dart';

class AdminMenuAction extends StatelessWidget {
  const AdminMenuAction({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    return FutureBuilder<bool>(
      future: AdminService(supabase).isCurrentUserAdmin(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.data != true) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: 'Manage Verifications',
          icon: const Icon(Icons.verified),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminVerificationPage()),
            );
          },
        );
      },
    );
  }
}
