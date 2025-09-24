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

  // Theme constants
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final authUser = sb.auth.currentUser;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: _bg,
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

            return Column(
              children: [
                // Header with gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_purple, _purpleDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 34,
                        backgroundImage: AssetImage(
                          'assets/images/avatar_placeholder.png',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (uid != null)
                              VerifiedBadge(userId: uid, size: 18),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Menu items
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _sectionTitle("General"),
                      _item(
                        icon: Icons.dashboard,
                        label: 'Dashboard',
                        highlight: true, // example active
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DashboardPage(),
                            ),
                          );
                        },
                      ),
                      _item(
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
                        icon: Icons.local_offer_outlined,
                        label: 'Promotion code',
                        onTap: () {},
                      ),
                      const Divider(),

                      _sectionTitle("Account"),
                      _item(
                        icon: Icons.help_outline,
                        label: 'How it works',
                        onTap: () {},
                      ),
                      _item(
                        icon: Icons.support_agent,
                        label: 'Support',
                        onTap: () {},
                      ),
                      _item(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: () {},
                      ),
                      _item(
                        icon: Icons.person_outline,
                        label: 'View Profile',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfilePage(),
                            ),
                          );
                        },
                      ),

                      if (isAdmin) ...[
                        const Divider(),
                        _sectionTitle("Admin"),
                        _item(
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
                          icon: Icons.verified_user,
                          label: 'Vehicle Verification',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => const AdminVehicleVerificationPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                // Logout
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: Colors.red.withOpacity(0.08),
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context)
                          ..pop()
                          ..popUntil((r) => r.isFirst);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: _purpleDark,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return ListTile(
      tileColor: highlight ? _purple.withOpacity(0.08) : null,
      leading: Icon(icon, color: highlight ? _purple : Colors.black87),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
          color: highlight ? _purple : Colors.black87,
        ),
      ),
      onTap: onTap,
    );
  }
}
