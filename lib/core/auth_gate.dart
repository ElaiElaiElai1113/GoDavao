import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/auth/presentation/reset_password_sheet.dart';

/// Wrap your whole app with this. It listens for auth events globally.
/// Particularly: when a password-recovery link opens the app (cold or warm),
/// Supabase emits `AuthChangeEvent.passwordRecovery` and we show the sheet.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child, this.navigatorKey});
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  NavigatorState get _nav =>
      (widget.navigatorKey?.currentState) ?? Navigator.of(context);

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        final ctx = _nav.context;
        await showModalBottomSheet<void>(
          context: ctx,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const ResetPasswordSheet(),
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
