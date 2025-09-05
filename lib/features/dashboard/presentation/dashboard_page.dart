import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:godavao/features/profile/presentation/app_drawer.dart';
import 'package:godavao/features/auth/presentation/auth_page.dart';
import 'package:godavao/features/maps/passenger_map_page.dart';
import 'package:godavao/features/routes/presentation/pages/driver_route_page.dart';
import 'package:godavao/features/ride_status/presentation/driver_rides_page.dart';
import 'package:godavao/features/verify/data/verification_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  // Overview counts
  bool _loadingOverview = true;
  int? _driverActiveRoutes;
  int? _driverPendingRequests;
  int? _passengerUpcoming;
  int? _passengerHistory;

  // Verification realtime
  final _verifSvc = VerificationService(Supabase.instance.client);
  VerificationStatus _verifStatus = VerificationStatus.unknown;
  StreamSubscription<VerificationStatus>? _verifSub;

  // Theme
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _verifSub?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final u = _sb.auth.currentUser;
    if (u == null) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (_) => false,
      );
      return;
    }
    try {
      // Keep the selection tight
      final res =
          await _sb
              .from('users')
              .select('id, name, role, vehicle_info, verification_status')
              .eq('id', u.id)
              .single();

      if (!mounted) return;
      setState(() {
        _user = res;

        // Seed enum from snapshot to prevent "pending" flash
        final vs = (res['verification_status'] ?? '').toString().toLowerCase();
        if (vs == 'verified' || vs == 'approved') {
          _verifStatus = VerificationStatus.verified; // backward-compatible
        } else if (vs == 'pending') {
          _verifStatus = VerificationStatus.pending;
        } else if (vs == 'rejected') {
          _verifStatus = VerificationStatus.rejected;
        } else {
          _verifStatus = VerificationStatus.unknown;
        }

        _loading = false;
      });

      // Start/restart realtime watcher
      _verifSub?.cancel();
      _verifSub = _verifSvc.watchStatus(userId: u.id).listen((s) {
        if (!mounted) return;
        setState(() => _verifStatus = s);
      });

      await _loadOverview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load profile.';
        _loading = false;
        _loadingOverview = false;
      });
    }
  }

  Future<void> _loadOverview() async {
    setState(() => _loadingOverview = true);
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loadingOverview = false);
      return;
    }
    final role = (_user?['role'] as String?) ?? 'passenger';

    try {
      if (role == 'driver') {
        final activeRoutes = await _sb
            .from('driver_routes')
            .select('id')
            .eq('driver_id', uid)
            .eq('is_active', true);
        final activeCount = (activeRoutes as List).length;

        final pendingMatches = await _sb
            .from('ride_matches')
            .select('id')
            .eq('driver_id', uid)
            .eq('status', 'pending');
        final pendingCount = (pendingMatches as List).length;

        if (!mounted) return;
        setState(() {
          _driverActiveRoutes = activeCount;
          _driverPendingRequests = pendingCount;
        });
      } else {
        final upcoming = await _sb
            .from('ride_requests')
            .select('id')
            .eq('passenger_id', uid)
            .inFilter('status', ['pending', 'accepted', 'en_route']);
        final upcomingCount = (upcoming as List).length;

        final history = await _sb
            .from('ride_requests')
            .select('id')
            .eq('passenger_id', uid)
            .inFilter('status', [
              'completed',
              'declined',
              'cancelled',
              'canceled',
            ]);
        final historyCount = (history as List).length;

        if (!mounted) return;
        setState(() {
          _passengerUpcoming = upcomingCount;
          _passengerHistory = historyCount;
        });
      }
    } catch (_) {
      // log or ignore
    } finally {
      if (mounted) setState(() => _loadingOverview = false);
    }
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = (_user?['role'] as String?) ?? 'passenger';
    final name = (_user?['name'] as String?) ?? 'GoDavao user';
    final vehicleInfo = _user?['vehicle_info'] as String?;
    final isDriver = role == 'driver';

    // Drive UI from enum
    final isVerified = _verifStatus == VerificationStatus.verified;

    final overviewLeftLabel = isDriver ? 'Active Routes' : 'Upcoming';
    final overviewLeftValue =
        isDriver
            ? _fmtCount(_driverActiveRoutes)
            : _fmtCount(_passengerUpcoming);
    final overviewRightLabel = isDriver ? 'Pending Requests' : 'Past Rides';
    final overviewRightValue =
        isDriver
            ? _fmtCount(_driverPendingRequests)
            : _fmtCount(_passengerHistory);

    return Scaffold(
      backgroundColor: _bg,
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async => _fetch(),
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _ErrorState(onRetry: _fetch, message: _error!)
                : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Builder(
                      builder:
                          (ctx) => _HeroHeader(
                            name: name,
                            role: role,
                            purple: _purple,
                            purpleDark: _purpleDark,
                            onMenu: () => Scaffold.of(ctx).openDrawer(),
                            onLogout: _logout,
                          ),
                    ),

                    const SizedBox(height: 16),

                    // Verification Banner (shows unless verified)
                    if (!isVerified)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning,
                                color: Colors.orange,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _statusText(_verifStatus, role),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder:
                                        (_) => VerifyIdentitySheet(role: role),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Verify'),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // DRIVER VEHICLE SUMMARY (only if verified)
                    if (isDriver && isVerified)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _VehicleCard(
                          vehicleInfo: vehicleInfo,
                          onManage: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DriverRoutePage(),
                              ),
                            );
                          },
                        ),
                      ),

                    // QUICK ACTIONS
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Quick Actions',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child:
                          isDriver
                              ? (isVerified
                                  ? _ActionGrid(
                                    items: [
                                      _ActionItem(
                                        title: 'Set Driver Route',
                                        subtitle: 'Go online',
                                        icon: Icons.alt_route,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) =>
                                                        const DriverRoutePage(),
                                              ),
                                            ),
                                      ),
                                      _ActionItem(
                                        title: 'Ride Matches',
                                        subtitle: 'Requests & trips',
                                        icon: Icons.groups_2,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) =>
                                                        const DriverRidesPage(),
                                              ),
                                            ),
                                      ),
                                    ],
                                  )
                                  : Container(
                                    padding: const EdgeInsets.all(16),
                                    child: const Text(
                                      'Driver features are locked until your verification is approved.',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ))
                              : _ActionGrid(
                                items: [
                                  _ActionItem(
                                    title: 'Book a Ride',
                                    subtitle: 'Pick route & seats',
                                    icon: Icons.map_outlined,
                                    onTap:
                                        () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => const PassengerMapPage(),
                                          ),
                                        ),
                                  ),
                                  _ActionItem(
                                    title: 'My Rides',
                                    subtitle: 'Upcoming & history',
                                    icon: Icons.receipt_long,
                                    onTap:
                                        () => Navigator.pushNamed(
                                          context,
                                          '/passenger_rides',
                                        ),
                                  ),
                                  _ActionItem(
                                    title: 'Settings',
                                    subtitle: 'Manage your preferences',
                                    icon: Icons.settings,
                                    onTap:
                                        () => Navigator.pushNamed(
                                          context,
                                          '/profile',
                                        ),
                                  ),
                                ],
                              ),
                    ),

                    // OVERVIEW (only if driver is verified or passenger)
                    if (!isDriver || isVerified) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Overview',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: overviewLeftLabel,
                                value:
                                    _loadingOverview ? '—' : overviewLeftValue,
                                icon: Icons.event_available,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: overviewRightLabel,
                                value:
                                    _loadingOverview ? '—' : overviewRightValue,
                                icon: Icons.history,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
      ),
    );
  }

  String _fmtCount(int? n) => n == null ? '—' : n.toString();

  String _statusText(VerificationStatus s, String role) {
    switch (s) {
      case VerificationStatus.pending:
        return role == 'driver'
            ? 'Your driver verification is pending. You cannot accept rides until approved.'
            : 'Your verification is pending.';
      case VerificationStatus.rejected:
        return role == 'driver'
            ? 'Your driver verification was rejected. Please resubmit.'
            : 'Your verification was rejected. Please resubmit.';
      case VerificationStatus.verified:
        return 'Verified';
      case VerificationStatus.unknown:
      default:
        return role == 'driver'
            ? 'You must complete verification before driving.'
            : 'Please verify your account.';
    }
  }
}

class _HeroHeader extends StatelessWidget {
  final String name;
  final String role;
  final Color purple;
  final Color purpleDark;

  final VoidCallback onMenu;
  final VoidCallback onLogout;

  const _HeroHeader({
    required this.name,
    required this.role,
    required this.purple,
    required this.purpleDark,
    required this.onMenu,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [purple, purpleDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: purple.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 25),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: onMenu,
                tooltip: 'Menu',
              ),
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: purpleDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Icon(
                      role == 'driver'
                          ? Icons.car_rental
                          : Icons.person_pin_circle,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      role.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: onLogout,
                tooltip: 'Logout',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _ActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

class _ActionGrid extends StatelessWidget {
  final List<_ActionItem> items;
  const _ActionGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (_, i) {
        final it = items[i];
        return InkWell(
          onTap: it.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(it.icon, color: Colors.black87, size: 26),
                  const Spacer(),
                  Text(
                    it.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    it.subtitle,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF1FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.analytics, color: Color(0xFF3A3F73)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final String? vehicleInfo;
  final VoidCallback onManage;
  const _VehicleCard({required this.vehicleInfo, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final info =
        (vehicleInfo == null || vehicleInfo!.trim().isEmpty)
            ? 'No vehicle on profile'
            : vehicleInfo!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF1FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.directions_car,
              size: 28,
              color: Color(0xFF3A3F73),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              info,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Manage'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const _ErrorState({required this.onRetry, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, color: Colors.red, size: 64),
        const SizedBox(height: 12),
        Center(child: Text(message, style: const TextStyle(fontSize: 18))),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AuthPage()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('Logout and Re-authenticate'),
        ),
      ],
    );
  }
}
