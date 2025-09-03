import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/history/presentation/booking_history_page.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/verify/presentation/admin_verification_page.dart';
import 'package:godavao/features/auth/presentation/auth_page.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  Future<void> _fetchUser() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final res =
        await supabase
            .from('users')
            .select('id, name, verification_status, is_admin')
            .eq('id', uid)
            .maybeSingle();
    setState(() {
      _user = res;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final name = _user?['name'] ?? 'GoDavao User';
    final status = _user?['verification_status'] ?? 'pending';
    final isAdmin = _user?['is_admin'] == true;

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

            // Header with avatar + name + verified dot/status
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            VerifiedBadge(userId: user?.id ?? '', size: 18),
                            const SizedBox(width: 6),
                            _statusChip(status),
                          ],
                        ),
                      ],
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
                  _item(context, Icons.dashboard, 'Dashboard', () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DashboardPage()),
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
                  _item(context, Icons.help_outline, 'How it works', () {}),
                  _item(context, Icons.support_agent, 'Support', () {}),
                  _item(context, Icons.settings_outlined, 'Settings', () {}),

                  // Admin-only section
                  if (isAdmin) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Text(
                        "Admin Section",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    _item(
                      context,
                      Icons.verified_user,
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
                  ],

                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text(
                      'Logout',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: _logout,
                  ),
                ],
              ),
            ),

            // Profile shortcut button
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

  Widget _statusChip(String status) {
    Color color;
    String text;
    switch (status) {
      case 'approved':
        color = Colors.green;
        text = 'Verified';
        break;
      case 'rejected':
        color = Colors.red;
        text = 'Rejected';
        break;
      default:
        color = Colors.orange;
        text = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
