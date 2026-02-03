import 'package:flutter/material.dart';
import 'admin_verification_page.dart';

class AdminMenuAction extends StatelessWidget {
  const AdminMenuAction({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.verified_user),
      title: const Text('Verification Review'),
      onTap: () {
        Navigator.pop(context);
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminVerificationPage()),
        );
      },
    );
  }
}
