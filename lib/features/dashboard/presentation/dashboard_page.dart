import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/presentation/auth_page.dart';
import '../../routes/presentation/pages/driver_route_page.dart';
import '../../maps/passenger_map_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? userInfo;
  bool loading = true;

  Future<void> fetchUserInfo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response =
        await supabase.from('users').select().eq('id', user.id).single();

    setState(() {
      userInfo = response;
      loading = false;
    });
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
  void initState() {
    super.initState();
    fetchUserInfo();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (userInfo == null) {
      return const Scaffold(
        body: Center(child: Text("Failed to load user info.")),
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
                  Navigator.pushNamed(context, '/testing');
                },
                child: const Text("Open Testing Dashboard"),
              ),
            ] else if (role == 'driver') ...[
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
                  Navigator.pushNamed(context, '/driver_rides');
                },
                child: const Text('View Ride Matches'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
