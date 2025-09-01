import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// If you use these routes, keep the imports.
// Otherwise replace the navigations below with your own.
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/auth/presentation/vehicle_form.dart';
import 'package:godavao/assets/Logo.jpg';

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

  // Brand palette
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
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
        final res = await _sb.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        if (res.user == null) throw 'Signup failed';

        await _sb.from('users').insert({
          'id': res.user!.id,
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'role': _role,
          'verified': false,
        });

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

                          // Logo
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const CircleAvatar(
                              radius: 60,
                              backgroundImage: AssetImage(
                                'lib/assets/Logo.jpg',
                              ),
                              backgroundColor: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 24),

                          Text(
                            _isLogin ? 'Welcome Back' : 'Create Account',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isLogin
                                ? 'Sign in to access your account'
                                : 'Join GoDavao to get started',
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Email
                          TextFormField(
                            controller: _emailCtrl,
                            style: const TextStyle(color: Colors.white),
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
                            style: const TextStyle(color: Colors.white),
                            obscureText: _obscure,
                            decoration: _fieldDecor(
                              label: 'Password',
                              hint: 'Enter your password',
                              suffix: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70,
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
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),

                          if (!_isLogin) ...[
                            TextFormField(
                              controller: _nameCtrl,
                              style: const TextStyle(color: Colors.white),
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
                              style: const TextStyle(color: Colors.white),
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
                              dropdownColor: Colors.deepPurple[700],
                              value: _role,
                              style: const TextStyle(color: Colors.white),
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
                                    color: _purpleDark.withOpacity(0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
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
                                            fontWeight: FontWeight.bold,
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
                                child: const Text(
                                  'Switch',
                                  style: TextStyle(
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
                              style: const TextStyle(color: Colors.redAccent),
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
