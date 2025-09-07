import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/history/presentation/booking_history_page.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/verify/presentation/admin_verification_page.dart';
import 'package:godavao/features/verify/presentation/admin_vehicle_verification_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final authUser = sb.auth.currentUser;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      child: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future:
              authUser == null
                  ? Future.value(null)
                  : sb
                      .from('users')
                      .select('id,name,verification_status,is_admin')
                      .eq('id', authUser.id)
                      .maybeSingle(),
          builder: (ctx, snap) {
            final userRow = snap.data ?? const <String, dynamic>{};
            final name =
                authUser == null
                    ? 'Not signed in'
                    : (userRow['name'] as String?) ?? 'GoDavao user';
            final uid = authUser?.id;
            final isAdmin = (userRow['is_admin'] as bool?) ?? false;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                // Close
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
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
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (uid != null)
                              VerifiedBadge(userId: uid, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Menu items
                _item(
                  context,
                  icon: Icons.dashboard,
                  label: 'Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const DashboardPage()),
                    );
                  },
                ),
                _item(
                  context,
                  icon: Icons.credit_card,
                  label: 'Payment methods',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment methods coming soon'),
                      ),
                    );
                  },
                ),
                _item(
                  context,
                  icon: Icons.history,
                  label: 'Booking History',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BookingHistoryPage(),
                      ),
                    );
                  },
                ),
                _item(
                  context,
                  icon: Icons.local_offer_outlined,
                  label: 'Promotion code',
                  onTap: () {},
                ),
                const Divider(),

                _item(
                  context,
                  icon: Icons.help_outline,
                  label: 'How it works',
                  onTap: () {},
                ),
                _item(
                  context,
                  icon: Icons.support_agent,
                  label: 'Support',
                  onTap: () {},
                ),
                _item(
                  context,
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () {},
                ),
                _item(
                  context,
                  icon: Icons.person_outline,
                  label: 'View Profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()),
                    );
                  },
                ),

                // Admin section
                if (isAdmin) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Admin',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _item(
                    context,
                    icon: Icons.verified_user_outlined,
                    label: 'Verification Review',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminVerificationPage(),
                        ),
                      );
                    },
                  ),
                  _item(
                    context,
                    icon: Icons.verified_user,
                    label: 'Vehicle Verification',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminVehicleVerificationPage(),
                        ),
                      );
                    },
                  ),
                ],

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
            );
          },
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
    );
  }
}
