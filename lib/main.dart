// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/dashboard/presentation/testing_dashboard_page.dart';
import 'package:godavao/features/maps/passenger_map_page.dart';
import 'package:godavao/features/ride_status/presentation/driver_rides_page.dart';
import 'package:godavao/features/ride_status/presentation/passenger_rides_page.dart';
import 'package:godavao/features/routes/presentation/pages/driver_route_page.dart';
import 'package:godavao/features/auth/presentation/auth_page.dart';

// Global local notifications plugin
final FlutterLocalNotificationsPlugin localNotify =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // load your .env
  await dotenv.load(fileName: ".env");

  // initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // initialize local notifications
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await localNotify.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  runApp(const GoDavaoApp());
}

class GoDavaoApp extends StatelessWidget {
  const GoDavaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoDavao Rideshare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      initialRoute: '/',
      routes: {
        '/dashboard': (context) => const DashboardPage(),
        '/driver_rides': (context) => const DriverRidesPage(),
        '/passenger_rides': (_) => const PassengerRidesPage(),
        '/testing': (context) => const TestingDashboardPage(),
        '/passenger_map': (context) => const PassengerMapPage(),
        '/driver_route': (context) => const DriverRoutePage(),
      },
      home: const SessionRouter(),
    );
  }
}

class SessionRouter extends StatelessWidget {
  const SessionRouter({super.key});

  Future<Widget> _getDashboard() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return const AuthPage();
    return const DashboardPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _getDashboard(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        return snapshot.data!;
      },
    );
  }
}
