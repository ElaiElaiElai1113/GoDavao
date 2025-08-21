import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// If you use these routes, keep the imports.
// Otherwise replace the navigations below with your own.
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/auth/presentation/vehicle_form.dart';

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

  // Brand palette to match your mock
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

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
      border: const UnderlineInputBorder(),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _purple, width: 2),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        // LOGIN (email + password)
        final res = await _sb.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        if (res.session == null) throw 'Login failed';
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
      } else {
        // SIGNUP
        final res = await _sb.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        if (res.user == null) throw 'Signup failed';

        // Insert profile row
        await _sb.from('users').insert({
          'id': res.user!.id,
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'role': _role,
          'verified': false,
        });

        if (!mounted) return;

        // Drivers go to vehicle onboarding
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
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
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
                        // Round Logo (like your mock)
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

                        // Headline + subtitle
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

                        // Email (login uses email only)
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _fieldDecor(
                            label: 'Email',
                            hint: 'Enter your email',
                          ),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Enter your email'
                                      : null,
                        ),
                        const SizedBox(height: 12),

                        // Password
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
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
                            if (v == null || v.isEmpty)
                              return 'Enter your password';
                            if (v.length < 6) return 'Password too short';
                            return null;
                          },
                        ),

                        // Forgot password (like the mock)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Signup-only fields (Name, Phone, Role)
                        if (!_isLogin) ...[
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: _fieldDecor(label: 'Full Name'),
                            validator:
                                (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Enter your name'
                                        : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _fieldDecor(label: 'Phone Number'),
                            validator:
                                (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Enter your phone'
                                        : null,
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
                            onChanged: (v) {
                              if (v != null) setState(() => _role = v);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Primary CTA (purple gradient)
                        const SizedBox(height: 16),
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
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.black54),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _isLogin = !_isLogin),
                              child: const Text(
                                'Switch',
                                style: TextStyle(
                                  color: _purple,
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
                            style: const TextStyle(color: Colors.red),
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
    );
  }
}
