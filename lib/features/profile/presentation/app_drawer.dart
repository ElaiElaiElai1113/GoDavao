import 'package:flutter/material.dart';
import 'package:godavao/features/history/presentation/booking_history_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      child: SafeArea(
        child: Column(
          children: [
            // Close button row
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            // Header with avatar + name + verified dot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundImage: AssetImage(
                      'assets/images/avatar_placeholder.png',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>?>(
                      future:
                          supabase
                              .from('users')
                              .select('id,name,verified')
                              .eq('id', user!.id)
                              .maybeSingle(),
                      builder: (ctx, snap) {
                        final name =
                            (snap.data as Map?)?['name'] as String? ?? '—';
                        final uid = user.id;
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            VerifiedBadge(userId: uid, size: 18),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Menu items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _item(context, Icons.credit_card, 'Payment methods', () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment methods coming soon'),
                      ),
                    );
                  }),
                  _item(context, Icons.history, 'Booking History', () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BookingHistoryPage()),
                    );
                  }),
                  _item(
                    context,
                    Icons.local_offer_outlined,
                    'Promotion code',
                    () {},
                  ),
                  const Divider(),
                  _item(context, Icons.help_outline, 'How it works', () {}),
                  _item(context, Icons.support_agent, 'Support', () {}),
                  _item(context, Icons.settings_outlined, 'Settings', () {}),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context)
                          ..pop() // close drawer
                          ..popUntil((r) => r.isFirst);
                      }
                    },
                  ),
                ],
              ),
            ),

            // Profile shortcut map peek is shown in Figma; use a button to open profile
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_outline),
                  label: const Text('View Profile'),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
    );
  }
}
