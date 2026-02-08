import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:godavao/common/app_colors.dart';

class PrivacyDisclaimerPage extends StatefulWidget {
  const PrivacyDisclaimerPage({super.key});

  @override
  State<PrivacyDisclaimerPage> createState() => _PrivacyDisclaimerPageState();
}

class _PrivacyDisclaimerPageState extends State<PrivacyDisclaimerPage> {
  // GoDavao brand
  static const _purple = AppColors.purple;
  static const _purpleDark = AppColors.purpleDark;
  static const _bg = Color(0xFFF7F7FB);

  bool _agreed = false;
  bool _loading = false;

  Future<void> _acceptTerms() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accepted_terms', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/dashboard');
  }

  void _showFullText(String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    body,
                    style: const TextStyle(height: 1.5, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Brand header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_purple, _purpleDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withValues(alpha: .25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  // If you have a logo, put it in assets and uncomment:
                  // Image.asset('assets/logo.png', height: 44),
                  // const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: _purpleDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Welcome to GoDavao',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Card ──────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.black12.withValues(alpha: .06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withValues(alpha: .06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Terms & Privacy',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Before using GoDavao, please review the key points below. '
                          'We process minimal personal data to provide rides, live tracking, and SOS alerts.',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        const _Bullet(
                          'Data we process: name, contact details, and GPS location while using the app.',
                        ),
                        const _Bullet(
                          'Location is required for matching rides and safety features (live tracking & SOS).',
                        ),
                        const _Bullet(
                          'SOS may share your current location with your trusted contacts.',
                        ),
                        const _Bullet(
                          'You can request data deletion and stop using the app at any time.',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('Read Terms'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _purple,
                              ),
                              onPressed:
                                  () => _showFullText(
                                    'GoDavao Terms of Service',
                                    _termsText,
                                  ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.privacy_tip_outlined),
                              label: const Text('Read Privacy Policy'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _purple,
                              ),
                              onPressed:
                                  () => _showFullText(
                                    'GoDavao Privacy Policy',
                                    _privacyText,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _agreed,
                              onChanged:
                                  (v) => setState(() => _agreed = v ?? false),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              activeColor: _purple,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'I have read and agree to the Terms of Service and Privacy Policy.',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                _agreed && !_loading ? _acceptTerms : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: _purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(_loading ? 'Saving…' : 'Continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6.0),
            child: Icon(Icons.circle, size: 6, color: Colors.black54),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
        ],
      ),
    );
  }
}

// ── Simple inline legal text (edit for your thesis/app) ───────────────
const String _termsText = '''
Welcome to GoDavao. By using this app, you agree to use it lawfully and responsibly.
You must provide accurate information and comply with community guidelines.
GoDavao may update these Terms from time to time.
''';

const String _privacyText = '''
GoDavao collects limited data (name, contact, GPS) to enable rides, live tracking,
and SOS features. Data is stored securely in Supabase and shared only as needed for
safety (e.g., your trusted contacts during SOS). You may request deletion of your data.
''';

