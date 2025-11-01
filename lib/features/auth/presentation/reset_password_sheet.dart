import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordSheet extends StatefulWidget {
  const ResetPasswordSheet({super.key});

  @override
  State<ResetPasswordSheet> createState() => _ResetPasswordSheetState();
}

class _ResetPasswordSheetState extends State<ResetPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pwd1 = TextEditingController();
  final _pwd2 = TextEditingController();
  bool _ob1 = true, _ob2 = true, _loading = false;
  String? _err;
  final _sb = Supabase.instance.client;

  @override
  void dispose() {
    _pwd1.dispose();
    _pwd2.dispose();
    super.dispose();
  }

  String? _validatePwd(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Enter a new password';
    if (s.length < 6) return 'Must be at least 6 characters';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pwd1.text != _pwd2.text) {
      setState(() => _err = 'Passwords do not match');
      return;
    }
    setState(() {
      _err = null;
      _loading = true;
    });

    try {
      await _sb.auth.updateUser(UserAttributes(password: _pwd1.text));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Please log in.')),
      );
    } on AuthException catch (e) {
      setState(() => _err = e.message);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Set a New Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter and confirm your new password.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _pwd1,
                    obscureText: _ob1,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _ob1 = !_ob1),
                        icon: Icon(
                          _ob1 ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: _validatePwd,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pwd2,
                    obscureText: _ob2,
                    decoration: InputDecoration(
                      labelText: 'Confirm password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _ob2 = !_ob2),
                        icon: Icon(
                          _ob2 ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    validator: _validatePwd,
                  ),
                ],
              ),
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child:
                    _loading
                        ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
