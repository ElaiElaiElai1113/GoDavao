import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../dashboard/presentation/dashboard_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();

  bool _isLogin = true;
  String _role = 'passenger';
  String? _error;

  Future<void> _auth() async {
    try {
      final supabase = Supabase.instance.client;

      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final res = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        await supabase.from('users').insert({
          'id': res.user!.id,
          'name': _nameController.text.trim(),
          'role': _role,
          'phone': _phoneController.text.trim(),
          'vehicle_info':
              _role == 'driver' ? _vehicleController.text.trim() : null,
          'verified': false,
        });
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = _role == 'driver';

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isLogin ? 'Login to GoDavao' : 'Register for GoDavao',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (!_isLogin) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                  ),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  DropdownButtonFormField<String>(
                    value: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: 'passenger',
                        child: Text('Passenger'),
                      ),
                      DropdownMenuItem(value: 'driver', child: Text('Driver')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _role = value);
                      }
                    },
                  ),
                  if (isDriver)
                    TextField(
                      controller: _vehicleController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Info',
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _auth,
                  child: Text(_isLogin ? 'Login' : 'Register'),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? 'No account? Register here'
                        : 'Already have an account? Login',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
