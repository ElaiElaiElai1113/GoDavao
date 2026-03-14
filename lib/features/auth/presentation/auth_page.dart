import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/common/app_colors.dart';
import 'package:godavao/common/app_shadows.dart';
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';
import 'package:godavao/features/verify/presentation/admin_panel_page.dart';
import 'package:godavao/features/verify/presentation/verify_identity_sheet.dart';

const _kAppDeepLink = 'io.supabase.godavao://reset-callback';

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

  static const _purple = AppColors.purple;
  static const _purpleDark = AppColors.purpleDark;

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
      labelStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.15),
      hintStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
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

  // ----- Forgot Password -----
  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter your email first.')));
      return;
    }
    try {
      await _sb.auth.resetPasswordForEmail(email, redirectTo: _kAppDeepLink);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset link sent! Open it on this device to continue.',
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  // ----- Data helpers -----
  Future<void> _ensureUserRow({
    required String userId,
    required String role,
    String? name,
    String? phone,
    required bool isSignup,
  }) async {
    final existing =
        await _sb
            .from('users')
            .select('id, verification_status')
            .eq('id', userId)
            .maybeSingle();

    final normalizedRole =
        (role == 'driver' || role == 'passenger') ? role : 'passenger';

    if (existing == null) {
      await _sb.from('users').insert({
        'id': userId,
        'name': (name?.trim().isEmpty ?? true) ? 'EMPTY' : name!.trim(),
        'role': normalizedRole,
        'phone': phone?.trim().isEmpty == true ? null : phone!.trim(),
        'verification_status': 'pending',
      });
    } else {
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

  Future<bool> _isAdmin(String userId) async {
    final row =
        await _sb
            .from('users')
            .select('is_admin')
            .eq('id', userId)
            .maybeSingle();
    return (row?['is_admin'] as bool?) ?? false;
  }

  Future<void> _promptVerify(String role) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VerifyIdentitySheet(role: role),
    );
  }

  // ----- Submit (login / signup) -----
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
          email: _emailCtrl.text.trim().toLowerCase(),
          password: _passwordCtrl.text,
        );
        final user = res.user;
        if (user == null) throw 'Login failed';

        final role = await _getRole(user.id) ?? 'passenger';
        await _ensureUserRow(userId: user.id, role: role, isSignup: false);

        final v = (await _getVerificationStatus(user.id))?.toLowerCase();
        final isVerified = v == 'verified' || v == 'approved';
        final isAdminUser = await _isAdmin(user.id);

        // maybe show verify sheet
        if (!isAdminUser && role == 'passenger' && !isVerified) {
          await _promptVerify(role);
        }

        if (!mounted) return;
        final landing =
            isAdminUser ? const AdminPanelPage() : const DashboardPage();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute<void>(builder: (_) => landing));
        });
      } else {
        // SIGNUP
        final email = _emailCtrl.text.trim().toLowerCase();
        final pwd = _passwordCtrl.text;
        final fullName = _nameCtrl.text.trim();
        final phone = _phoneCtrl.text.trim();

        final res = await _sb.auth.signUp(
          email: email,
          password: pwd,
          emailRedirectTo: _kAppDeepLink,
          data: {'name': fullName, 'phone': phone, 'role': _role},
        );
        final user = res.user;
        if (user == null) throw 'Signup failed';

        await _ensureUserRow(
          userId: user.id,
          role: _role,
          name: fullName,
          phone: phone,
          isSignup: true,
        );

        if (_role == 'passenger') {
          await _promptVerify(_role);
        }

        if (!mounted) return;
        final isAdminUser = await _isAdmin(user.id);
        final landing =
            isAdminUser ? const AdminPanelPage() : const DashboardPage();

        // ✅ same trick for signup
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute<void>(builder: (_) => landing));
        });
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

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final whiteBody = textTheme.bodyMedium?.copyWith(color: Colors.white);
    final whiteLabel = textTheme.labelLarge?.copyWith(color: Colors.white);
    final whiteTitle = textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );

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
                              boxShadow: AppShadows.card,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: const CircleAvatar(
                                radius: 60,
                                backgroundImage: AssetImage(
                                  'lib/assets/Logo.jpg',
                                ),
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            _isLogin ? 'Welcome' : 'Create your account',
                            style: whiteTitle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isLogin
                                ? 'Sign in to book rides around Davao.'
                                : 'Join GoDavao to start riding or driving.',
                            style: whiteBody,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            style: whiteBody,
                            decoration: _fieldDecor(
                              label: 'Email',
                              hint: 'you@example.com',
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Enter your email';
                              if (!s.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction:
                                _isLogin
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                            onFieldSubmitted: (_) {
                              if (_isLogin) _submit();
                            },
                            style: whiteBody,
                            decoration: _fieldDecor(
                              label: 'Password',
                              hint: 'Enter your password',
                              suffix: IconButton(
                                style: IconButton.styleFrom(
                                  foregroundColor: Colors.white.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
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
                              final s = v ?? '';
                              if (s.isEmpty) return 'Enter your password';
                              if (s.length < 6) return 'Password too short';
                              return null;
                            },
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _forgotPassword,
                              child: Text(
                                'Forgot Password?',
                                style: whiteLabel,
                              ),
                            ),
                          ),

                          if (!_isLogin) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              style: whiteBody,
                              decoration: _fieldDecor(label: 'Full Name'),
                              validator:
                                  (v) =>
                                      _isLogin
                                          ? null
                                          : ((v ?? '').trim().isEmpty
                                              ? 'Enter your name'
                                              : null),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              style: whiteBody,
                              decoration: _fieldDecor(label: 'Phone Number'),
                              validator:
                                  (v) =>
                                      _isLogin
                                          ? null
                                          : ((v ?? '').trim().isEmpty
                                              ? 'Enter your phone'
                                              : null),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _role,
                              decoration: _fieldDecor(label: 'Role'),
                              dropdownColor: _purpleDark,
                              iconEnabledColor: Colors.white,
                              iconDisabledColor: Colors.white.withValues(
                                alpha: 0.75,
                              ),
                              style: whiteBody,
                              items: [
                                DropdownMenuItem(
                                  value: 'passenger',
                                  child: Text(
                                    'Passenger',
                                    style: whiteBody,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'driver',
                                  child: Text(
                                    'Driver',
                                    style: whiteBody,
                                  ),
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
                            height: 50,
                            child: FilledButton(
                              onPressed: _loading ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                              child:
                                  _loading
                                      ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.black,
                                          ),
                                        ),
                                      )
                                      : Text(
                                        _isLogin ? 'Login' : 'Register',
                                        style: textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
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
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              TextButton(
                                onPressed:
                                    () => setState(() => _isLogin = !_isLogin),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  _isLogin ? 'Register' : 'Login',
                                  style: textTheme.labelLarge?.copyWith(
                                    color: Colors.white,
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
                              style: textTheme.bodyMedium?.copyWith(
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
