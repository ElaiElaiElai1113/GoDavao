import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/presentation/auth_page.dart';
import '../../maps/passenger_map_page.dart';
import '../../routes/presentation/pages/driver_route_page.dart';
import '../../ride_status/presentation/driver_rides_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? userInfo;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchUserInfo();
  }

  Future<void> fetchUserInfo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response =
          await supabase.from('users').select().eq('id', user.id).single();

      setState(() {
        userInfo = response;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching user info: $e");
      setState(() => loading = false);
    }
  }

  void _logout() async {
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
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (userInfo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("GoDavao")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 12),
                const Text(
                  "Failed to load user info.",
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: fetchUserInfo,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout and Re-authenticate"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final name = userInfo!['name'] ?? 'N/A';
    final role = userInfo!['role'] ?? 'N/A';
    final vehicle = userInfo!['vehicle_info'] ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('GoDavao Dashboard'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome, $name",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text("Role: $role"),
            if (role == 'driver') Text("Vehicle Info: $vehicle"),
            const SizedBox(height: 24),

            // Passenger UI
            if (role == 'passenger') ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PassengerMapPage()),
                  );
                },
                child: const Text("Book a Ride"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/passenger_rides');
                },
                child: const Text("View My Rides"),
              ),
            ],

            // Driver UI
            if (role == 'driver') ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverRoutePage()),
                  );
                },
                child: const Text("Set Driver Route"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverRidesPage()),
                  );
                },
                child: const Text("View Ride Matches"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
