import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';

class VehicleForm extends StatefulWidget {
  const VehicleForm({super.key});

  @override
  State<VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  int _seats = 4;
  bool _loading = false;
  String? _error;

  static const _purple = Color(0xFF6A27F7);

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    super.dispose();
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    border: const UnderlineInputBorder(),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: _purple, width: 2),
    ),
  );

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser!.id;

      await sb.from('vehicles').insert({
        'driver_id': uid,
        'make': _make.text.trim(),
        'model': _model.text.trim(),
        'plate': _plate.text.trim(),
        'color': _color.text.trim(),
        'seats': _seats,
        'is_default': true,
      });

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
        (_) => false,
      );
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
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(title: const Text('Your Vehicle')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _make,
                decoration: _decor('Make (e.g., Toyota)'),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _model,
                decoration: _decor('Model (e.g., Vios)'),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _plate,
                decoration: _decor('Plate Number'),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _color, decoration: _decor('Color')),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Seats'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _seats,
                    items:
                        [1, 2, 3, 4, 5, 6, 7, 8]
                            .map(
                              (n) =>
                                  DropdownMenuItem(value: n, child: Text('$n')),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _seats = v ?? 4),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _save,
                  child:
                      _loading
                          ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Save & Continue'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
