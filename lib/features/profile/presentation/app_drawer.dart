// lib/features/profile/presentation/app_drawer.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/history/presentation/booking_history_page.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/verify/presentation/admin_panel_page.dart';
import 'package:godavao/features/profile/presentation/how_it_works_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  // Theme constants
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _textDim = Color(0xFF667085);

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final authUser = sb.auth.currentUser;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: _bg,
      child: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: authUser == null
              ? Future.value(null)
              : sb
                  .from('users')
                  .select('id, name, phone, verification_status, is_admin')
                  .eq('id', authUser.id)
                  .maybeSingle(),
          builder: (ctx, snap) {
            final isLoading = snap.connectionState == ConnectionState.waiting;
            final userRow = (snap.data ?? const <String, dynamic>{});
            final name = authUser == null
                ? 'Not signed in'
                : (userRow['name'] as String?)?.trim().isNotEmpty == true
                    ? (userRow['name'] as String)
                    : 'GoDavao user';
            final email = authUser?.email ?? '';
            final uid = authUser?.id;
            final isAdmin = (userRow['is_admin'] as bool?) ?? false;
            final verification =
                (userRow['verification_status'] as String?) ?? 'unverified';

            return Column(
              children: [
                // Header with gradient, with skeleton for loading
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_purple, _purpleDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 34,
                        backgroundImage: AssetImage(
                          'assets/images/avatar_placeholder.png',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: isLoading
                            ? const _HeaderSkeleton()
                            : Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Name
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

    // Email
    if (email.isNotEmpty)
      Text(
        email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontSize: 12.5,
        ),
      ),

    const SizedBox(height: 8),

    // Chips row (left-aligned under the text above)
    Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Verified / Unverified chip
          Builder(
            builder: (context) {
              final isVerified =
                  verification == 'approved' || verification == 'verified';
              return _chip(
                label: isVerified ? 'Verified' : 'Unverified',
                bg: Colors.white.withOpacity(0.18),
                fg: Colors.white,
                icon: isVerified ? Icons.verified : Icons.shield_moon_outlined,
              );
            },
          ),

          // Optional Admin chip
          if (isAdmin)
            _chip(
              label: 'Admin',
              bg: Colors.white.withOpacity(0.18),
              fg: Colors.white,
              icon: Icons.admin_panel_settings,
            ),
        ],
      ),
    ),
  ],
),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),

                // Quick Actions row
                if (!isLoading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      children: [
                        _quickAction(
                          icon: Icons.person_outline,
                          label: 'Profile',
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
                        const SizedBox(width: 10),
                        _quickAction(
                          icon: Icons.help_outline,
                          label: 'How it works',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HowItWorksPage(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        _quickAction(
                          icon: Icons.history_rounded,
                          label: 'History',
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
                      ],
                    ),
                  ),

                const SizedBox(height: 4),

                // Menu items
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _sectionTitle("General"),
                      _item(
                        icon: Icons.dashboard,
                        label: 'Dashboard',
                        subtitle: 'View map, routes, and requests',
                        highlight: true,
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
                        icon: Icons.history,
                        label: 'Booking History',
                        subtitle: 'See past and current rides',
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

                      const Divider(height: 24),

                      _sectionTitle("Account"),
                      _item(
                        icon: Icons.help_outline,
                        label: 'How it works',
                        subtitle: 'Short guide to get started',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HowItWorksPage(),
                            ),
                          );
                        },
                      ),
                      _item(
                        icon: Icons.person_outline,
                        label: 'View Profile',
                        subtitle: 'Edit name, email, phone',
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
                        const Divider(height: 24),
                        _sectionTitle("Admin"),
                        _item(
                          icon: Icons.admin_panel_settings,
                          label: 'Admin Panel',
                          subtitle: 'Manage verification & reports',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminPanelPage(),
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
                    subtitle: const Text(
                      'Sign out of your account',
                      style: TextStyle(color: _textDim),
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

  static Widget _chip({
    required String label,
    required Color bg,
    required Color fg,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: fg),
          if (icon != null) const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _purple),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: _purpleDark,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    bool highlight = false,
  }) {
    return ListTile(
      minTileHeight: 54,
      tileColor: highlight ? _purple.withOpacity(0.08) : null,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor:
            highlight ? _purple.withOpacity(0.12) : Colors.black.withOpacity(0.06),
        child: Icon(
          icon,
          color: highlight ? _purple : Colors.black87,
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
          color: highlight ? _purple : Colors.black87,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: _textDim))
          : null,
      onTap: onTap,
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 10}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(140, h: 14),
        const SizedBox(height: 6),
        bar(180),
        const SizedBox(height: 10),
        Row(
          children: [bar(70, h: 12), const SizedBox(width: 8), bar(60, h: 12)],
        ),
      ],
    );
  }
}