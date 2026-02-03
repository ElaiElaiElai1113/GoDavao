import 'dart:async';

import 'package:flutter/material.dart';
import 'package:godavao/features/verify/presentation/AdminFeedbackPage.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/verify/presentation/admin_verification_page.dart';
import 'package:godavao/features/verify/presentation/admin_vehicle_verification_page.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  static const _purple = Color(0xFF6A27F7);
  static const _bg = Color(0xFFF7F7FB);

  final _sb = Supabase.instance.client;
  late final NumberFormat _numberFmt;

  int? _totalUsers;
  int? _totalDrivers;
  int? _totalPassengers;
  int? _pendingVerification;
  int? _pendingVehicles;
  int? _verifiedDrivers;
  int? _verifiedPassengers;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _numberFmt = NumberFormat.decimalPattern();
    unawaited(_fetchStats());
  }

  Future<void> _fetchStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await _sb
          .from('users')
          .select('role, verification_status, verified_role, name');

      int totalUsers = users.length;
      int drivers = 0;
      int passengers = 0;
      int pending = 0;
      int verifiedDrivers = 0;
      int verifiedPassengers = 0;

      for (final row in users) {
        final role = (row['role']?.toString() ?? '').toLowerCase();
        final status =
            (row['verification_status']?.toString() ?? '').toLowerCase();
        final verifiedRole =
            (row['verified_role']?.toString() ?? '').toLowerCase();

        if (role == 'driver') drivers++;
        if (role == 'passenger') passengers++;

        if (status == 'pending') pending++;

        if (verifiedRole == 'driver') {
          verifiedDrivers++;
        } else if (verifiedRole == 'passenger') {
          verifiedPassengers++;
        } else if (status == 'verified' || status == 'approved') {
          if (role == 'driver') {
            verifiedDrivers++;
          } else if (role == 'passenger') {
            verifiedPassengers++;
          }
        }
      }

      int? pendingVehicles;
      const vehicleSources = [
        {'table': 'vehicle_verification_requests', 'column': 'status'},
        {'table': 'vehicle_reviews', 'column': 'status'},
        {'table': 'vehicles', 'column': 'verification_status'},
      ];

      for (final source in vehicleSources) {
        final table = source['table']!;
        final column = source['column']!;
        try {
          final rows = await _sb.from(table).select(column);
          int count = 0;
          for (final row in rows) {
            final status = (row[column]?.toString() ?? '').toLowerCase();
            if (status == 'pending' || status == 'under_review') count++;
          }
          pendingVehicles = count;
          break;
        } on PostgrestException {
          continue;
        }
      }

      setState(() {
        _totalUsers = totalUsers;
        _totalDrivers = drivers;
        _totalPassengers = passengers;
        _pendingVerification = pending;
        _verifiedDrivers = verifiedDrivers;
        _verifiedPassengers = verifiedPassengers;
        _pendingVehicles = pendingVehicles;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load admin stats. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  String _fmt(int? v) => v == null ? '—' : _numberFmt.format(v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchStats,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchStats,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              _ErrorBanner(message: _error!, onRetry: _fetchStats)
            else
              _StatsGrid(
                loading: _loading,
                totalUsers: _fmt(_totalUsers),
                totalDrivers: _fmt(_totalDrivers),
                totalPassengers: _fmt(_totalPassengers),
                verifiedDrivers: _fmt(_verifiedDrivers),
                verifiedPassengers: _fmt(_verifiedPassengers),
                pendingVerification: _fmt(_pendingVerification),
                pendingVehicles: _fmt(_pendingVehicles),
              ),
            const SizedBox(height: 16),
            _SectionHeader(
              title: 'Moderation Tools',
              subtitle:
                  'Review identity documents and vehicle submissions requiring attention.',
            ),
            const SizedBox(height: 12),
            _AdminTile(
              icon: Icons.verified_user_outlined,
              title: 'Verification Review',
              badgeLabel: 'Pending: ${_fmt(_pendingVerification)}',
              description:
                  'Pending passengers: review IDs and supporting documents before approval.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminVerificationPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _AdminTile(
              icon: Icons.directions_car,
              title: 'Vehicle Verification',
              badgeLabel: 'Pending: ${_fmt(_pendingVehicles)}',
              description:
                  'Pending vehicles: check OR/CR, insurance and photos before activating drivers.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminVehicleVerificationPage(),
                  ),
                );
              },
            ),
            _AdminTile(
              icon: Icons.reviews_outlined,
              title: 'User Feedback & Ratings',
              badgeLabel: 'View All',
              description:
                  'See feedback and scores given by passengers or drivers across the platform.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminFeedbackPage()),
                );
              },
            ),

            const SizedBox(height: 28),
            _SectionHeader(
              title: 'Account',
              subtitle: 'Manage your admin session.',
            ),
            const SizedBox(height: 12),
            _LogoutButton(onPressed: _logout),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.loading,
    required this.totalUsers,
    required this.totalDrivers,
    required this.totalPassengers,
    required this.verifiedDrivers,
    required this.verifiedPassengers,
    required this.pendingVerification,
    required this.pendingVehicles,
  });

  final bool loading;
  final String totalUsers;
  final String totalDrivers;
  final String totalPassengers;
  final String verifiedDrivers;
  final String verifiedPassengers;
  final String pendingVerification;
  final String pendingVehicles;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatCard(
        icon: Icons.people_alt_rounded,
        label: 'Total Users',
        value: totalUsers,
        loading: loading,
      ),
      _StatCard(
        icon: Icons.directions_car_filled,
        label: 'Drivers',
        value: totalDrivers,
        loading: loading,
      ),
      _StatCard(
        icon: Icons.person_pin,
        label: 'Passengers',
        value: totalPassengers,
        loading: loading,
      ),
      _StatCard(
        icon: Icons.verified,
        label: 'Verified Drivers',
        value: verifiedDrivers,
        loading: loading,
      ),
      _StatCard(
        icon: Icons.verified_user,
        label: 'Verified Passengers',
        value: verifiedPassengers,
        loading: loading,
      ),
      _StatCard(
        icon: Icons.verified_user_outlined,
        label: 'Pending Verifications',
        value: pendingVerification,
        loading: loading,
      ),
      _StatCard(
        icon: Icons.garage_outlined,
        label: 'Pending Vehicles',
        value: pendingVehicles,
        loading: loading,
      ),
    ];

    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.loading,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool loading;

  static const _gradient = LinearGradient(
    colors: [Colors.white, Color(0xFFF5F3FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 22,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _gradient,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF3F2A8C)),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF3F2A8C),
              ),
            ),
            const SizedBox(height: 6),
            loading
                ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Color(0xFF1A1435),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.icon,
    required this.title,
    required this.badgeLabel,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String badgeLabel;
  final String description;
  final VoidCallback onTap;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Colors.white, Color(0xFFF5F3FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_purple, _purpleDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF20124D),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _purple,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1435),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.55),
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.withValues(alpha: 0.12),
        foregroundColor: Colors.red.shade700,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.logout),
      label: const Text(
        'Log out',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Unable to load stats',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
