// lib/features/dashboard/presentation/dashboard_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';
import 'package:godavao/features/ride_status/presentation/passenger_myrides_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/routes/presentation/pages/driver_routes_list_tab.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:godavao/features/profile/presentation/app_drawer.dart';
import 'package:godavao/features/auth/presentation/auth_page.dart';
import 'package:godavao/features/maps/passenger_map_page.dart';
import 'package:godavao/features/routes/presentation/pages/driver_route_page.dart';
import 'package:godavao/features/ride_status/presentation/driver_rides_page.dart';
import 'package:godavao/features/verify/data/verification_service.dart';
// Vehicles
import 'package:godavao/features/vehicles/presentation/vehicles_page.dart';
// ✅ Trusted Contacts (new)
import 'package:godavao/features/safety/presentation/trusted_contacts_page.dart';

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

  // ✅ Safety: trusted contacts count
  int? _trustedCount;

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
      final res =
          await _sb
              .from('users')
              .select('id, name, role, verification_status')
              .eq('id', u.id)
              .single();

      if (!mounted) return;
      setState(() {
        _user = res;

        final vs = (res['verification_status'] ?? '').toString().toLowerCase();
        if (vs == 'verified' || vs == 'approved') {
          _verifStatus = VerificationStatus.verified;
        } else if (vs == 'pending') {
          _verifStatus = VerificationStatus.pending;
        } else if (vs == 'rejected') {
          _verifStatus = VerificationStatus.rejected;
        } else {
          _verifStatus = VerificationStatus.unknown;
        }

        _loading = false;
      });

      // realtime watcher
      _verifSub?.cancel();
      _verifSub = _verifSvc.watchStatus(userId: u.id).listen((s) {
        if (!mounted) return;
        setState(() => _verifStatus = s);
      });

      await _loadOverview();
    } catch (_) {
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

        final pendingMatches = await _sb
            .from('ride_matches')
            .select('id')
            .eq('driver_id', uid)
            .eq('status', 'pending');

        if (!mounted) return;
        setState(() {
          _driverActiveRoutes = (activeRoutes as List).length;
          _driverPendingRequests = (pendingMatches as List).length;
        });
      } else {
        final upcoming = await _sb
            .from('ride_requests')
            .select('id')
            .eq('passenger_id', uid)
            .inFilter('status', ['pending', 'accepted', 'en_route']);

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

        if (!mounted) return;
        setState(() {
          _passengerUpcoming = (upcoming as List).length;
          _passengerHistory = (history as List).length;
        });
      }

      // ✅ Also load trusted contacts count for Safety banner + stat
      try {
        final tcs = await _sb
            .from('trusted_contacts')
            .select('id')
            .eq('user_id', uid);
        if (mounted) setState(() => _trustedCount = (tcs as List).length);
      } catch (_) {
        // non-fatal
      }
    } catch (_) {
      // non-fatal
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
    final isDriver = role == 'driver';
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
        onRefresh: _fetch,
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
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
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
                                child: const Text(
                                  'Verify',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ✅ Safety banner when no trusted contacts yet
                    if ((_trustedCount ?? 0) == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person,
                                color: Colors.indigo,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Set up trusted contacts so we can notify family or friends during SOS.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => const TrustedContactsPage(),
                                    ),
                                  ).then((_) => _loadOverview());
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Set up'),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // QUICK ACTIONS
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Quick Actions',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child:
                          isDriver
                              ? (
                              // DRIVER
                              isVerified
                                  ? _ActionGrid(
                                    items: [
                                      _ActionItem(
                                        title: 'Vehicles',
                                        subtitle: 'Add & verify car',
                                        icon:
                                            Icons
                                                .directions_car_filled_outlined,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => const VehiclesPage(),
                                              ),
                                            ),
                                      ),
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
                                        title: 'My Routes',
                                        subtitle: 'View & manage',
                                        icon: Icons.route_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const DriverRoutesListTab(),
                                            ),
                                          );
                                        },
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
                                      // ✅ Trusted Contacts (driver verified)
                                      _ActionItem(
                                        title: 'Trusted Contacts',
                                        subtitle: 'Safety settings',
                                        icon: Icons.person,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const TrustedContactsPage(),
                                            ),
                                          ).then((_) => _loadOverview());
                                        },
                                      ),
                                    ],
                                  )
                                  : _ActionGrid(
                                    items: [
                                      _ActionItem(
                                        title: 'Vehicles',
                                        subtitle: 'Add & verify car',
                                        icon:
                                            Icons
                                                .directions_car_filled_outlined,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => const VehiclesPage(),
                                              ),
                                            ),
                                      ),
                                      // ✅ Trusted Contacts (driver unverified)
                                      _ActionItem(
                                        title: 'Trusted Contacts',
                                        subtitle: 'Safety settings',
                                        icon: Icons.person,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const TrustedContactsPage(),
                                            ),
                                          ).then((_) => _loadOverview());
                                        },
                                      ),
                                    ],
                                  ))
                              : _ActionGrid(
                                // PASSENGER
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
                                        () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) =>
                                                    const PassengerMyRidesPage(),
                                          ),
                                        ),
                                  ),
                                  _ActionItem(
                                    title: 'Settings',
                                    subtitle: 'Manage your preferences',
                                    icon: Icons.settings,
                                    onTap:
                                        () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const ProfilePage(),
                                          ),
                                        ),
                                  ),
                                  // ✅ Trusted Contacts (passenger)
                                  _ActionItem(
                                    title: 'Trusted Contacts',
                                    subtitle: 'Safety settings',
                                    icon: Icons.person,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) =>
                                                  const TrustedContactsPage(),
                                        ),
                                      ).then((_) => _loadOverview());
                                    },
                                  ),
                                ],
                              ),
                    ),

                    // OVERVIEW (only if driver is verified OR user is passenger)
                    if (!isDriver || isVerified) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Overview',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      // (Optional) show safety stat below
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _StatCard(
                          label: 'Trusted Contacts',
                          value:
                              _loadingOverview ? '—' : _fmtCount(_trustedCount),
                          icon: Icons.person,
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
                      'Welcome',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      role == 'driver'
                          ? Icons.car_rental
                          : Icons.person_pin_circle,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        role.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
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

class BottomCard extends StatelessWidget {
  final Widget child;
  const BottomCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final List<_ActionItem> items;
  const _ActionGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6A27F7);
    const accentDark = Color(0xFF4B18C9);
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
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [accent, accentDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(it.icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    it.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    it.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    const accent = Color(0xFF6A27F7);
    const accentDark = Color(0xFF4B18C9);
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
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [accent, accentDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text(
            'Retry',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
          label: const Text(
            'Logout and Re-authenticate',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
