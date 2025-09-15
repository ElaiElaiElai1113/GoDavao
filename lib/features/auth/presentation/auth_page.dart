import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Existing routes
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/auth/presentation/vehicle_form.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;
  String _role = 'passenger';
  String? _error;

  final _sb = Supabase.instance.client;

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecor({String? hint, String? label, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.15),
      hintStyle: const TextStyle(color: Colors.white54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      suffixIcon: suffix,
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter your email first.')));
      return;
    }
    try {
      await _sb.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  // ---------------------------------------------------------------------------
  // Data helpers
  // ---------------------------------------------------------------------------

  /// **Idempotent** user row creation. On signup we seed a row with
  /// verification_status='unverified' (or 'pending' if you prefer).
  /// On login we DO NOT touch verification_status.
  Future<void> _ensureUserRow({
    required String userId,
    required String role,
    String? name,
    String? phone,
    required bool isSignup, // still passed, but logic changes
  }) async {
    // read current row
    final existing =
        await _sb
            .from('users')
            .select('id, verification_status')
            .eq('id', userId)
            .maybeSingle();

    final normalizedRole =
        (role == 'driver' || role == 'passenger') ? role : 'passenger';

    if (existing == null) {
      // no row yet (e.g., trigger disabled) -> insert with pending
      await _sb.from('users').insert({
        'id': userId,
        'name': (name?.trim().isEmpty ?? true) ? 'EMPTY' : name!.trim(),
        'role': normalizedRole,
        'phone': phone?.trim().isEmpty == true ? null : phone!.trim(),
        'verification_status': 'pending', // or omit to use DB default
      });
    } else {
      // row exists (usually because the trigger created it) -> ALWAYS update fields
      final patch = <String, dynamic>{
        'role': normalizedRole,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      };
      if (patch.isNotEmpty) {
        await _sb.from('users').update(patch).eq('id', userId);
      }
    }
  }

  Future<String?> _getVerificationStatus(String userId) async {
    final row =
        await _sb
            .from('users')
            .select('verification_status')
            .eq('id', userId)
            .maybeSingle();
    return row?['verification_status'] as String?;
  }

  Future<String?> _getRole(String userId) async {
    final row =
        await _sb.from('users').select('role').eq('id', userId).maybeSingle();
    return row?['role'] as String?;
  }

  Future<void> _promptVerify(String role) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VerifyIdentitySheet(role: role),
    );
  }

  // ---------------------------------------------------------------------------
  // Submit (login / signup)
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        // -------------------- LOGIN --------------------
        final res = await _sb.auth.signInWithPassword(
          email: _emailCtrl.text.trim().toLowerCase(),
          password: _passwordCtrl.text,
        );
        final user = res.user;
        if (user == null) throw 'Login failed';

        // Get role from DB (fallback passenger)
        final role = await _getRole(user.id) ?? 'passenger';

        // Ensure row exists, but DO NOT reset verification_status on login
        await _ensureUserRow(userId: user.id, role: role, isSignup: false);

        // Check status; treat 'verified' and legacy 'approved' as verified
        final v = (await _getVerificationStatus(user.id))?.toLowerCase();
        final isVerified = v == 'verified' || v == 'approved';

        if (!isVerified) {
          await _promptVerify(role);
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
      } else {
        // -------------------- SIGNUP --------------------
        final email = _emailCtrl.text.trim().toLowerCase();
        final pwd = _passwordCtrl.text;
        final fullName = _nameCtrl.text.trim();
        final phone = _phoneCtrl.text.trim();

        // Send auth metadata too (helps if you keep a provisioning trigger)
        final res = await _sb.auth.signUp(
          email: email,
          password: pwd,
          data: {'name': fullName, 'phone': phone, 'role': _role},
        );
        final user = res.user;
        if (user == null) throw 'Signup failed';

        // Create users row (first time). We start unverified.
        await _ensureUserRow(
          userId: user.id,
          role: _role,
          name: fullName,
          phone: phone,
          isSignup: true,
        );

        // Immediately prompt for verification
        await _promptVerify(_role);

        if (!mounted) return;

        if (_role == 'driver') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const VehicleForm()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on PostgrestException catch (e) {
      // surface useful PostgREST messages
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_purple, _purpleDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final maxW = c.maxWidth;
              final contentW = maxW > 420 ? 420.0 : maxW;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: contentW),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const CircleAvatar(
                              radius: 60,
                              backgroundImage: AssetImage(
                                'assets/images/godavao_logo.png',
                              ),
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            _isLogin ? 'Welcome back' : 'Create your account',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isLogin
                                ? 'Sign in to book rides around Davao.'
                                : 'Join GoDavao to start riding or driving.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: _fieldDecor(
                              label: 'Email',
                              hint: 'you@example.com',
                            ),
                            validator: (v) {
                              final s = v?.trim() ?? '';
                              if (s.isEmpty) return 'Enter your email';
                              if (!s.contains('@'))
                                return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            decoration: _fieldDecor(
                              label: 'Password',
                              hint: 'Enter your password',
                              suffix: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed:
                                    () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Enter your password';
                              }
                              if (v.length < 6) return 'Password too short';
                              return null;
                            },
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _forgotPassword,
                              child: const Text('Forgot Password?'),
                            ),
                          ),

                          if (!_isLogin) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: _fieldDecor(label: 'Full Name'),
                              validator: (v) {
                                if (_isLogin) return null;
                                return (v == null || v.trim().isEmpty)
                                    ? 'Enter your name'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: _fieldDecor(label: 'Phone Number'),
                              validator: (v) {
                                if (_isLogin) return null;
                                return (v == null || v.trim().isEmpty)
                                    ? 'Enter your phone'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _role,
                              decoration: _fieldDecor(label: 'Role'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'passenger',
                                  child: Text('Passenger'),
                                ),
                                DropdownMenuItem(
                                  value: 'driver',
                                  child: Text('Driver'),
                                ),
                              ],
                              onChanged:
                                  (v) =>
                                      setState(() => _role = v ?? 'passenger'),
                            ),
                          ],

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [_purple, _purpleDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _purple.withOpacity(0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _loading ? null : _submit,
                                child:
                                    _loading
                                        ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                        : Text(
                                          _isLogin ? 'Login' : 'Register',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLogin ? 'or ' : 'Already have an account? ',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              GestureDetector(
                                onTap:
                                    () => setState(() => _isLogin = !_isLogin),
                                child: Text(
                                  _isLogin ? 'Register' : 'Login',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
