import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/verify/presentation/verified_badge.dart';
import 'package:godavao/features/profile/presentation/app_drawer.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;

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
    if (au == null) return;

    try {
      final row =
          await supabase
              .from('users')
              .select('name, phone')
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
    setState(() => _saving = true);

    final supabase = Supabase.instance.client;
    final au = supabase.auth.currentUser!;
    try {
      await supabase
          .from('users')
          .update({'name': _name.text.trim(), 'phone': _phone.text.trim()})
          .eq('id', au.id);

      if (_email.text.trim().isNotEmpty &&
          _email.text.trim() != (au.email ?? '')) {
        await supabase.auth.updateUser(
          UserAttributes(email: _email.text.trim()),
        );
      }
      if (_password.text.isNotEmpty) {
        await supabase.auth.updateUser(
          UserAttributes(password: _password.text),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6A27F7);
    const purpleDark = Color(0xFF4B18C9);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final uid = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      drawer: const AppDrawer(), // ✅ Drawer added
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // HERO HEADER (same style as Dashboard)
          Builder(
            builder:
                (ctx) => _HeroHeader(
                  purple: purple,
                  purpleDark: purpleDark,
                  onMenu: () => Scaffold.of(ctx).openDrawer(),
                ),
          ),

          // PROFILE FORM
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + verified badge
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        backgroundImage: AssetImage(
                          'assets/images/avatar_placeholder.png',
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: VerifiedBadge(userId: uid, size: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _label('Full name'),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    hintText: 'Your name',
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                _label('Email address'),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'name@example.com',
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                _label('Phone number'),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '09xxxxxxxxx',
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                _label('Password'),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    border: const UnderlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save button with gradient
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
                      boxShadow: [
                        BoxShadow(
                          color: purple.withOpacity(0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
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
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : const Text(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.black54,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// Custom Hero-style header (like DashboardPage)
class _HeroHeader extends StatelessWidget {
  final Color purple;
  final Color purpleDark;
  final VoidCallback onMenu;

  const _HeroHeader({
    required this.purple,
    required this.purpleDark,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [purple, purpleDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: onMenu,
          ),
          const SizedBox(width: 8),
          const Text(
            'Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
