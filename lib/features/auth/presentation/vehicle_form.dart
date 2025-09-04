import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  File? _orcrFile;
  final _picker = ImagePicker();

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _pickOrcr() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x != null) setState(() => _orcrFile = File(x.path));
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.black12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _purple, width: 2),
    ),
  );

  Future<void> _save() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    if (_orcrFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload OR/CR document")),
      );
      return;
    }

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
        // optionally save file path here if you integrate upload
        'orcr_path': '${uid}/orcr.jpg',
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
      appBar: AppBar(
        title: const Text('Register Vehicle'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Form fields inside cards
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _make,
                          decoration: _decor('Make (e.g., Toyota)'),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _model,
                          decoration: _decor('Model (e.g., Vios)'),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _plate,
                          decoration: _decor('Plate Number'),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _color,
                          decoration: _decor('Color'),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text(
                              'Seats',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<int>(
                              value: _seats,
                              borderRadius: BorderRadius.circular(12),
                              items:
                                  [2, 3, 4, 5, 6, 7, 8]
                                      .map(
                                        (n) => DropdownMenuItem(
                                          value: n,
                                          child: Text('$n'),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) => setState(() => _seats = v ?? 4),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ORCR Upload card
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: const Text(
                      'Upload OR/CR Document',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _orcrFile == null
                          ? 'Required for driver verification'
                          : _orcrFile!.path.split('/').last,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.upload_file, color: _purple),
                      onPressed: _pickOrcr,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Save button
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
                      onPressed: _loading ? null : _save,
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
                              : const Text(
                                'Save & Continue',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                    ),
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
      ),
    );
  }
}
