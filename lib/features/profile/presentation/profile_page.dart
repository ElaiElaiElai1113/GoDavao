// lib/features/profile/presentation/profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/profile/presentation/app_drawer.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;

  static const purple = Color(0xFF6A27F7);
  static const purpleDark = Color(0xFF4B18C9);
  static const textDim = Color(0xFF667085);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final supabase = Supabase.instance.client;
    final au = supabase.auth.currentUser;
    if (au == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final row =
          await supabase
              .from('users')
              .select('name, phone, verification_status')
              .eq('id', au.id)
              .maybeSingle();

      setState(() {
        _name.text = (row as Map?)?['name'] as String? ?? '';
        _phone.text = (row as Map?)?['phone'] as String? ?? '';
        _email.text = au.email ?? '';
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final supabase = Supabase.instance.client;
    final au = supabase.auth.currentUser!;
    try {
      // Update profile table
      await supabase
          .from('users')
          .update({'name': _name.text.trim(), 'phone': _phone.text.trim()})
          .eq('id', au.id);

      // Update auth email if changed
      final emailNew = _email.text.trim();
      if (emailNew.isNotEmpty && emailNew != (au.email ?? '')) {
        await supabase.auth.updateUser(UserAttributes(email: emailNew));
      }

      // Update password if provided
      if (_password.text.isNotEmpty) {
        await supabase.auth.updateUser(
          UserAttributes(password: _password.text),
        );
        _password.clear();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profile updated successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final uid = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  purple.withOpacity(0.95),
                  purple.withOpacity(0.6),
                  purple.withOpacity(0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.22, 0.45, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Content
          SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // App bar row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Builder(
                        builder:
                            (ctx) => IconButton(
                              icon: const Icon(Icons.menu, color: Colors.white),
                              onPressed: () => Scaffold.of(ctx).openDrawer(),
                              tooltip: 'Menu',
                            ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Avatar + badge
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      const CircleAvatar(
                        radius: 48,
                        backgroundImage: AssetImage(
                          'assets/images/avatar_placeholder.png',
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: VerifiedBadge(userId: uid, size: 22),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Card with form
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _titleRow(
                          title: 'Account details',
                          subtitle:
                              'Keep your info up to date so drivers and passengers can reach you.',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 8),

                        _label('Full name'),
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Your full name',
                            border: UnderlineInputBorder(),
                          ),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Please enter your name'
                                      : null,
                        ),
                        const SizedBox(height: 16),

                        _label('Email address'),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'name@example.com',
                            border: UnderlineInputBorder(),
                            helperText:
                                'Changing your email may require re-confirmation.',
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Email is required';
                            final ok = RegExp(
                              r"^[^\s@]+@[^\s@]+\.[^\s@]+$",
                            ).hasMatch(t);
                            return ok ? null : 'Enter a valid email';
                          },
                        ),
                        const SizedBox(height: 16),

                        _label('Phone number'),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            hintText: '09XXXXXXXXX',
                            border: UnderlineInputBorder(),
                            helperText: 'Used for contacting you about rides.',
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return null; // optional
                            if (t.length < 10) return 'Enter a valid phone';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        _label('Change password (optional)'),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            hintText: 'New password',
                            border: const UnderlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed:
                                  () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip: _obscure ? 'Show' : 'Hide',
                            ),
                            helperText:
                                'Leave blank to keep your current password.',
                          ),
                          validator: (v) {
                            if ((v ?? '').isEmpty) return null;
                            if ((v ?? '').length < 6) return 'Min 6 characters';
                            return null;
                          },
                        ),

                        const SizedBox(height: 22),

                        // Save button with gradient background
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [purple, purpleDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _saving ? null : _save,
                              child:
                                  _saving
                                      ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                      : const Text(
                                        'Save changes',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: textDim,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _titleRow({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFF2EEFF),
          child: Icon(icon, color: purple, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: textDim, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
