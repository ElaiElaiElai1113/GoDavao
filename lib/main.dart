import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'features/auth/presentation/auth_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/maps/passenger_map_page.dart';
import 'features/ride_status/presentation/driver_rides_page.dart';
import 'features/ride_status/presentation/passenger_rides_page.dart';
import 'features/routes/presentation/pages/driver_route_page.dart';

import 'features/chat/data/chat_subscription_service.dart';
import 'features/chat/data/chat_messages_service.dart';

// Global local notifications plugin
final FlutterLocalNotificationsPlugin localNotify =
    FlutterLocalNotificationsPlugin();

// RouteObserver for listening to navigation events
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// Navigator Key for OSRM
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // init local notifications
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await localNotify.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  // instantiate chat services
  final subService = ChatSubscriptionService()..start();
  final msgService = ChatMessagesService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: subService),
        ChangeNotifierProvider.value(value: msgService),
      ],
      child: const GoDavaoApp(),
    ),
  );
}

class GoDavaoApp extends StatelessWidget {
  const GoDavaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoDavao Rideshare',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      initialRoute: '/',
      routes: {
        '/dashboard': (_) => const DashboardPage(),
        '/driver_rides': (_) => const DriverRidesPage(),
        '/passenger_rides': (_) => const PassengerRidesPage(),
        '/passenger_map': (_) => const PassengerMapPage(),
        '/driver_route': (_) => const DriverRoutePage(),
      },
      home: const SessionRouter(),
    );
  }
}

class SessionRouter extends StatelessWidget {
  const SessionRouter({super.key});

  Future<Widget> _getInitial() async {
    final client = Supabase.instance.client;
    return client.auth.currentUser == null
        ? const AuthPage()
        : const DashboardPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _getInitial(),
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (s.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${s.error}')));
        }
        return s.data!;
      },
    );
  }
}
