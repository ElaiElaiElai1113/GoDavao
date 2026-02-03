import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/auth/presentation/auth_page.dart';
import 'package:godavao/features/profile/presentation/profile_page.dart';
import 'package:godavao/features/profile/presentation/app_drawer.dart';

import 'package:godavao/features/maps/passenger_map_page.dart';
import 'package:godavao/features/ride_status/presentation/passenger_myrides_page.dart';

import 'package:godavao/features/routes/presentation/pages/driver_route_page.dart';
import 'package:godavao/features/routes/presentation/pages/driver_routes_list_tab.dart';
import 'package:godavao/features/ride_status/presentation/driver_rides_page.dart';

import 'package:godavao/features/vehicles/presentation/vehicles_page.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';
import 'package:godavao/features/verify/data/verification_service.dart';
import 'package:godavao/features/verify/presentation/pending_banner.dart'; // ✅ NEW

import 'package:godavao/features/safety/presentation/trusted_contacts_page.dart';

import 'package:postgrest/postgrest.dart' show PostgrestException, CountOption;


// 🟣 Coach marks
import 'package:godavao/common/tutorial/coach_overlay.dart';
import 'package:godavao/common/tutorial/tutorial_service.dart';

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

  // ✅ Verification realtime + submitted timestamp (for banner)
  final _verifSvc = VerificationService(Supabase.instance.client);
  VerificationStatus _verifStatus = VerificationStatus.unknown;
  StreamSubscription<VerificationStatus>? _verifSub;
  DateTime? _verifSubmittedAt; // ✅ NEW: last submission time

  // Theme
  static const _bg = Color(0xFFF7F7FB);
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  // =========================
  // Coach overlay wiring
  // =========================
  bool _showTutorial = false;
  final _verifyBtnKey = GlobalKey();
  // Passenger keys
  final _qaBookRideKey = GlobalKey();
  final _qaMyRidesKey = GlobalKey();
  final _qaTrustedKey = GlobalKey();
  // Driver keys
  final _qaVehiclesKey = GlobalKey();
  final _qaSetRouteKey = GlobalKey();
  final _qaRideMatchesKey = GlobalKey();

  List<CoachStep> _tutorialSteps = const [];

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
      MaterialPageRoute<void>(builder: (_) => const AuthPage()),
      (_) => false,
    );
    return;
  }

  try {
    // tolerant profile fetch
    final res = await _sb
        .from('users')
        .select('id, name, role, verification_status')
        .eq('id', u.id)
        .maybeSingle();

    if (!mounted) return;

    final row = (res as Map<String, dynamic>?) ??
        {
          'id': u.id,
          'name': (u.userMetadata?['full_name'] ??
                   u.userMetadata?['name'] ??
                   u.email ??
                   'GoDavao user'),
          'role': 'passenger',
          'verification_status': 'unknown',
        };

    setState(() {
      _user = row;
      final vs = (row['verification_status'] ?? '').toString().toLowerCase();
      _verifStatus = (vs == 'verified' || vs == 'approved')
          ? VerificationStatus.verified
          : (vs == 'pending')
              ? VerificationStatus.pending
              : (vs == 'rejected')
                  ? VerificationStatus.rejected
                  : VerificationStatus.unknown;
      _loading = false;
    });

    // latest verification submission (best effort)
    try {
      final req = await _sb
          .from('verification_requests')
          .select('created_at')
          .eq('user_id', u.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _verifSubmittedAt = (req?['created_at'] != null)
              ? DateTime.tryParse(req!['created_at'].toString())
              : null;
        });
      }
    } catch (_) {/* ignore */}

    // realtime watcher
    _verifSub?.cancel();
    _verifSub = _verifSvc.watchStatus(userId: u.id).listen((s) {
      if (!mounted) return;
      setState(() => _verifStatus = s);
    });

  } on PostgrestException catch (e) {
    if (!mounted) return;
    setState(() {
      _error = 'Profile query failed: ${e.message}';
      _loading = false;
      _loadingOverview = false;
    });
    return;
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _error = 'Failed to load profile: $e';
      _loading = false;
      _loadingOverview = false;
    });
    return;
  }

  // Run overview separately so errors here don’t show as “profile failed”
  await _loadOverview();

  // Decide if we show tutorial (after first frame)
  WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
}


  Future<void> _loadOverview() async {
  setState(() => _loadingOverview = true);

  final uid = _sb.auth.currentUser?.id;
  if (uid == null) {
    if (mounted) setState(() => _loadingOverview = false);
    return;
  }

  int _len(dynamic res) => (res is List) ? res.length : 0;

  try {
    final role = (_user?['role'] as String?) ?? 'passenger';

    if (role == 'driver') {
      final activeRoutes = await _sb
          .from('driver_routes')
          .select('id')
          .eq('driver_id', uid)
          .eq('is_active', true);

      final pendingReqs = await _sb
          .from('ride_matches')
          .select('id')
          .eq('driver_id', uid)
          .eq('status', 'pending');

      if (!mounted) return;
      setState(() {
        _driverActiveRoutes = _len(activeRoutes);
        _driverPendingRequests = _len(pendingReqs);
      });
    } else {
  // PASSENGER
  const up = ['pending', 'accepted', 'en_route'];
  const hist = ['completed', 'declined', 'canceled', 'cancelled'];

  int upcomingCount = 0;
  int pastCount = 0;

  try {
    // Pull current-user rides exactly like PassengerMyRidesPage
    final rows = await _sb
        .rpc<List<Map<String, dynamic>>>('passenger_rides_for_user')
        .select('id, effective_status');

    final list = (rows as List).cast<Map>();
    for (final r in list) {
      final s = (r['effective_status']?.toString() ?? '').toLowerCase();
      if (up.contains(s)) {
        upcomingCount++;
      } else if (hist.contains(s)) {
        pastCount++;
      }
    }
  } catch (e) {
    // OPTIONAL: tiny fallback (still less accurate than RPC)
    final upRows = await _sb
        .from('ride_requests')
        .select('id')
        .eq('passenger_id', _sb.auth.currentUser!.id)
        .inFilter('status', up);
    final hiRows = await _sb
        .from('ride_requests')
        .select('id')
        .eq('passenger_id', _sb.auth.currentUser!.id)
        .inFilter('status', hist);
    upcomingCount = (upRows is List) ? upRows.length : 0;
    pastCount     = (hiRows is List) ? hiRows.length : 0;
  }

  if (!mounted) return;
  setState(() {
    _passengerUpcoming = upcomingCount;
    _passengerHistory  = pastCount;
  });
}

    // Trusted contacts (best effort)
    try {
      final tcs = await _sb
          .from('trusted_contacts')
          .select('id')
          .eq('user_id', uid);
      if (mounted) setState(() => _trustedCount = _len(tcs));
    } catch (_) {/* ignore */}

  } catch (_) {
    // swallow overview errors; UI will just show "—"
  } finally {
    if (mounted) setState(() => _loadingOverview = false);
  }
}

  // =========================
  // Tutorial logic
  // =========================
  Future<void> _maybeShowTutorial() async {
    final seen = await TutorialService.getDashboardSeen();
    if (seen) return;

    final role = (_user?['role'] as String?) ?? 'passenger';
    final isDriver = role == 'driver';
    final isVerified = _verifStatus == VerificationStatus.verified;

    final steps = <CoachStep>[];

    // If not verified, highlight the verify CTA.
    if (!isVerified) {
      steps.add(
        CoachStep(
          key: _verifyBtnKey,
          title: 'Verify your account',
          description:
              isDriver
                  ? 'Before you can accept rides as a driver, please complete verification.'
                  : 'Verification helps keep our community safe. It also improves your match success.',
        ),
      );
    }

    if (!isDriver) {
      // Passenger flow
      steps.addAll([
        CoachStep(
          key: _qaBookRideKey,
          title: 'Book a Ride',
          description:
              'Tap here to choose pickup and destination, preview your route, and request a ride.',
        ),
        CoachStep(
          key: _qaMyRidesKey,
          title: 'Track Your Rides',
          description:
              'All your pending, ongoing, and past trips live here. You can check status anytime.',
        ),
        CoachStep(
          key: _qaTrustedKey,
          title: 'Safety: Trusted Contacts',
          description:
              'Add a trusted contact so we can notify family or friends during an SOS.',
        ),
      ]);
    } else if (isDriver && !isVerified) {
      // Driver (unverified)
      steps.addAll([
        CoachStep(
          key: _qaVehiclesKey,
          title: 'Add Your Vehicle',
          description:
              'Upload and verify your car to get ready for accepting ride matches.',
        ),
        CoachStep(
          key: _qaTrustedKey,
          title: 'Safety: Trusted Contacts',
          description: 'Set up a trusted contact to boost your safety.',
        ),
      ]);
    } else {
      // Driver (verified)
      steps.addAll([
        CoachStep(
          key: _qaSetRouteKey,
          title: 'Set Driver Route',
          description:
              'Go online by setting your route. We’ll start matching you with nearby passengers.',
        ),
        CoachStep(
          key: _qaRideMatchesKey,
          title: 'Ride Matches',
          description:
              'See and manage ride requests that match your route. Accept to start the trip.',
        ),
        CoachStep(
          key: _qaTrustedKey,
          title: 'Safety: Trusted Contacts',
          description:
              'Add a trusted contact so someone gets notified in case of emergency.',
        ),
      ]);
    }

    if (steps.isEmpty) return;

    setState(() {
      _tutorialSteps = steps;
      _showTutorial = true;
    });
  }

  void _finishTutorial() async {
    await TutorialService.setDashboardSeen();
    if (mounted) setState(() => _showTutorial = false);
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute<void>(builder: (_) => const AuthPage()),
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
      body: Stack(
        children: [
          RefreshIndicator(
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

                        // ✅ Verification banners
                        if (_verifStatus == VerificationStatus.pending)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: PendingVerificationBanner(
                              role: role,
                              submittedAt: _verifSubmittedAt,
                              onReviewTap: () {
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder:
                                      (_) => VerifyIdentitySheet(role: role),
                                );
                              },
                            ),
                          )
                        else if (!isVerified)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.shade300,
                                ),
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
                                    key: _verifyBtnKey, // tutorial target
                                    onPressed: () {
                                      showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        useSafeArea: true,
                                        builder:
                                            (_) =>
                                                VerifyIdentitySheet(role: role),
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
                                border: Border.all(
                                  color: Colors.indigo.shade200,
                                ),
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder:
                                              (_) =>
                                                  const TrustedContactsPage(),
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
                                  ? (isVerified
                                      ? _ActionGrid(
                                        items: [
                                          _ActionItem(
                                            key: _qaVehiclesKey,
                                            title: 'Vehicles',
                                            subtitle: 'Add & verify car',
                                            icon:
                                                Icons
                                                    .directions_car_filled_outlined,
                                            onTap:
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute<void>(
                                                    builder:
                                                        (_) =>
                                                            const VehiclesPage(),
                                                  ),
                                                ),
                                          ),
                                          _ActionItem(
                                            key: _qaSetRouteKey,
                                            title: 'Set Driver Route',
                                            subtitle: 'Go online',
                                            icon: Icons.alt_route,
                                            onTap:
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute<void>(
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
                                                MaterialPageRoute<void>(
                                                  builder:
                                                      (_) =>
                                                          const DriverRoutesListTab(),
                                                ),
                                              );
                                            },
                                          ),
                                          _ActionItem(
                                            key: _qaRideMatchesKey,
                                            title: 'Ride Matches',
                                            subtitle: 'Requests & trips',
                                            icon: Icons.groups_2,
                                            onTap:
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute<void>(
                                                    builder:
                                                        (_) =>
                                                            const DriverRidesPage(),
                                                  ),
                                                ),
                                          ),
                                          _ActionItem(
                                            key: _qaTrustedKey,
                                            title: 'Trusted Contacts',
                                            subtitle: 'Safety settings',
                                            icon: Icons.person,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
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
                                            key: _qaVehiclesKey,
                                            title: 'Vehicles',
                                            subtitle: 'Add & verify car',
                                            icon:
                                                Icons
                                                    .directions_car_filled_outlined,
                                            onTap:
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute<void>(
                                                    builder:
                                                        (_) =>
                                                            const VehiclesPage(),
                                                  ),
                                                ),
                                          ),
                                          _ActionItem(
                                            key: _qaTrustedKey,
                                            title: 'Trusted Contacts',
                                            subtitle: 'Safety settings',
                                            icon: Icons.person,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute<void>(
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
                                        key: _qaBookRideKey,
                                        title: 'Book a Ride',
                                        subtitle: 'Pick route & seats',
                                        icon: Icons.map_outlined,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder:
                                                    (_) =>
                                                        const PassengerMapPage(),
                                              ),
                                            ),
                                      ),
                                      _ActionItem(
                                        key: _qaMyRidesKey,
                                        title: 'My Rides',
                                        subtitle: 'Upcoming & history',
                                        icon: Icons.receipt_long,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder:
                                                    (_) =>
                                                        const PassengerMyRidesPage(),
                                              ),
                                            ),
                                      ),
                                      _ActionItem(
                                        title: 'Settings',
                                        subtitle: 'Manage preferences',
                                        icon: Icons.settings,
                                        onTap:
                                            () => Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder:
                                                    (_) => const ProfilePage(),
                                              ),
                                            ),
                                      ),
                                      _ActionItem(
                                        key: _qaTrustedKey,
                                        title: 'Trusted Contacts',
                                        subtitle: 'Safety settings',
                                        icon: Icons.person,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute<void>(
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
                                        _loadingOverview
                                            ? '—'
                                            : overviewLeftValue,
                                    icon: Icons.event_available,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: overviewRightLabel,
                                    value:
                                        _loadingOverview
                                            ? '—'
                                            : overviewRightValue,
                                    icon: Icons.history,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _StatCard(
                              label: 'Trusted Contacts',
                              value:
                                  _loadingOverview
                                      ? '—'
                                      : _fmtCount(_trustedCount),
                              icon: Icons.person,
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),
                      ],
                    ),
          ),

          // Coach overlay on top of everything
          if (_showTutorial && _tutorialSteps.isNotEmpty)
            CoachOverlay(steps: _tutorialSteps, onFinish: _finishTutorial),
        ],
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

// =========================
// Header, grids, cards, etc.
// =========================

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
            color: purple.withValues(alpha: 0.25),
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
                  color: Colors.white.withValues(alpha: .15),
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
  final Key? key;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _ActionItem({
    this.key,
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
                color: Colors.black.withValues(alpha: 0.1),
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
          key: it.key, // 🔑 tutorial anchor
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
                          color: accent.withValues(alpha: 0.25),
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
                  color: accent.withValues(alpha: 0.25),
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
              MaterialPageRoute<void>(builder: (_) => const AuthPage()),
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
