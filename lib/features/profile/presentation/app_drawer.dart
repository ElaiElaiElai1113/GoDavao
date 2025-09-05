import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/verify/presentation/admin_vehicle_verification_page.dart';

import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/history/presentation/booking_history_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';
import 'package:godavao/features/verify/presentation/admin_verification_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final authUser = sb.auth.currentUser;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      child: SafeArea(
        child: Column(
          children: [
            // Close row
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            // Header
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
                    child:
                        authUser == null
                            ? const Text('Not signed in')
                            : FutureBuilder<Map<String, dynamic>?>(
                              future:
                                  sb
                                      .from('users')
                                      .select(
                                        'id,name,verification_status,is_admin',
                                      )
                                      .eq('id', authUser.id)
                                      .maybeSingle(),
                              builder: (ctx, snap) {
                                final data =
                                    (snap.data ?? const <String, dynamic>{});
                                final name =
                                    (data['name'] as String?) ?? 'GoDavao user';
                                final uid = authUser.id;

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
              child: FutureBuilder<Map<String, dynamic>?>(
                future:
                    authUser == null
                        ? Future.value(null)
                        : sb
                            .from('users')
                            .select('id,is_admin')
                            .eq('id', authUser.id)
                            .maybeSingle(),
                builder: (ctx, snap) {
                  final isAdmin =
                      ((snap.data ?? const {})['is_admin'] as bool?) ?? false;

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _item(context, Icons.dashboard, 'Dashboard', () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DashboardPage(),
                          ),
                        );
                      }),
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
                          MaterialPageRoute(
                            builder: (_) => const BookingHistoryPage(),
                          ),
                        );
                      }),
                      _item(
                        context,
                        Icons.local_offer_outlined,
                        'Promotion code',
                        () {},
                      ),
                      const Divider(),

                      // Profile / Settings
                      _item(context, Icons.help_outline, 'How it works', () {}),
                      _item(context, Icons.support_agent, 'Support', () {}),
                      _item(
                        context,
                        Icons.settings_outlined,
                        'Settings',
                        () {},
                      ),
                      _item(context, Icons.person_outline, 'View Profile', () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfilePage(),
                          ),
                        );
                      }),

                      // Admin section (visible only if is_admin = true)
                      if (isAdmin) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Admin',
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _item(
                          context,
                          Icons.verified_user_outlined,
                          'Verification Review',
                          () {
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
                          Icons.verified_user,
                          'Vehicle Verification',
                          () {
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

                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text(
                          'Logout',
                          style: TextStyle(color: Colors.red),
                        ),
                        onTap: () async {
                          await sb.auth.signOut();
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
