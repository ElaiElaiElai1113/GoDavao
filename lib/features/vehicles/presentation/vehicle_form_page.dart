import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:godavao/features/vehicles/data/vehicle_service.dart';
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';

class VehicleForm extends StatefulWidget {
  const VehicleForm({super.key});

  @override
  State<VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  final _svc = VehiclesService(Supabase.instance.client);
  final _picker = ImagePicker();

  // Theme
  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _bg = Color(0xFFF7F7FB);

  // Base fields
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _year = TextEditingController();
  int _seats = 4;
  bool _isDefault = false;

  // OR/CR numbers (for search/filter in admin)
  final _orNumber = TextEditingController();
  final _crNumber = TextEditingController();

  // OR/CR files (separate)
  File? _orFile;
  File? _crFile;

  // State
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _year.dispose();
    _orNumber.dispose();
    _crNumber.dispose();
    super.dispose();
  }

  InputDecoration _decor(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
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

  Future<void> _pickFile(bool isOR) async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() {
      if (isOR) {
        _orFile = File(x.path);
      } else {
        _crFile = File(x.path);
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveDraft() async {
    // Save without requiring OR/CR files (can upload later)
    if (_working) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _working = true);
    try {
      await _svc.createVehicle(
        make: _make.text.trim(),
        model: _model.text.trim(),
        plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        year:
            _year.text.trim().isEmpty ? null : int.tryParse(_year.text.trim()),
        seats: _seats,

        orNumber: _orNumber.text.trim().isEmpty ? null : _orNumber.text.trim(),
        crNumber: _crNumber.text.trim().isEmpty ? null : _crNumber.text.trim(),
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('Saved as Draft'),
              content: const Text(
                'You can upload OR & CR later from My Vehicles.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
        (_) => false,
      );
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _submitForVerification() async {
    // Requires both OR & CR files + numbers
    if (_working) return;
    if (!_formKey.currentState!.validate()) return;

    if (_orNumber.text.trim().isEmpty || _crNumber.text.trim().isEmpty) {
      _toast('Please enter both OR number and CR number.');
      return;
    }
    if (_orFile == null || _crFile == null) {
      _toast('Please upload both OR and CR documents.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      // 1) Create the vehicle first (no docs yet, status still default)
      await _svc.createVehicle(
        make: _make.text.trim(),
        model: _model.text.trim(),
        plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        year:
            _year.text.trim().isEmpty ? null : int.tryParse(_year.text.trim()),
        seats: _seats,

        orNumber: _orNumber.text.trim(),
        crNumber: _crNumber.text.trim(),
      );

      // 2) Fetch the latest created vehicle (simplest approach: get default or latest)
      final mine = await _svc.listMine();
      if (mine.isEmpty) throw Exception('Vehicle row was not created.');
      final vehicleId = mine.first['id'] as String;

      // 3) Upload OR/CR files
      await _svc.uploadOR(vehicleId: vehicleId, file: _orFile!);
      await _svc.uploadCR(vehicleId: vehicleId, file: _crFile!);

      // 4) Mark as submitted for verification
      await _svc.submitForVerificationBoth(vehicleId);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('Submitted for Verification'),
              content: const Text(
                'Your vehicle has been submitted. You’ll be notified once reviewed.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
        (_) => false,
      );
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
      _toast(e.message);
    } catch (e) {
      setState(() => _error = e.toString());
      _toast('Submit failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Register Vehicle'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Vehicle details
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SectionHeader(
                          icon: Icons.directions_car,
                          text: 'Vehicle Details',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _make,
                          decoration: _decor('Make *', hint: 'e.g., Toyota'),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _model,
                          decoration: _decor('Model *', hint: 'e.g., Vios'),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _plate,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _decor('Plate Number *'),
                          validator:
                              (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Required'
                                      : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _color,
                                decoration: _decor('Color'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _year,
                                keyboardType: TextInputType.number,
                                decoration: _decor('Year'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InputDecorator(
                                decoration: _decor('Seats *'),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _seats,
                                    items:
                                        [2, 3, 4, 5, 6, 7, 8]
                                            .map(
                                              (n) => DropdownMenuItem(
                                                value: n,
                                                child: Text('$n'),
                                              ),
                                            )
                                            .toList(),
                                    onChanged:
                                        (v) => setState(() => _seats = v ?? 4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SwitchListTile(
                                value: _isDefault,
                                onChanged:
                                    (v) => setState(() => _isDefault = v),
                                title: const Text('Set as default'),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // OR section
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SectionHeader(
                          icon: Icons.receipt_long,
                          text: 'Official Receipt (OR)',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _orNumber,
                          decoration: _decor(
                            'OR Number',
                            hint: 'For admin search/filter',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DocPickerRow(
                          label: 'Upload OR',
                          fileName: _orFile?.path.split('/').last,
                          onPick: () => _pickFile(true),
                          onClear:
                              _orFile == null
                                  ? null
                                  : () => setState(() => _orFile = null),
                        ),
                        if (_orFile != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _orFile!,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // CR section
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SectionHeader(
                          icon: Icons.badge,
                          text: 'Certificate of Registration (CR)',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _crNumber,
                          decoration: _decor(
                            'CR Number',
                            hint: 'For admin search/filter',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DocPickerRow(
                          label: 'Upload CR',
                          fileName: _crFile?.path.split('/').last,
                          onPick: () => _pickFile(false),
                          onClear:
                              _crFile == null
                                  ? null
                                  : () => setState(() => _crFile = null),
                        ),
                        if (_crFile != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _crFile!,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],

                const SizedBox(height: 20),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _working ? null : _saveDraft,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Save & Finish Later'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [_purple, _purpleDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _purple.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _working ? null : _submitForVerification,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child:
                                _working
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Text(
                                      'Submit for Verification',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------- Small UI widgets ---------------- */

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
  }
}

class _DocPickerRow extends StatelessWidget {
  const _DocPickerRow({
    required this.label,
    required this.fileName,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black12),
              ),
            ),
            child: Text(
              fileName ?? 'No file selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Choose file',
          icon: const Icon(Icons.upload_file),
          onPressed: onPick,
        ),
        if (onClear != null)
          IconButton(
            tooltip: 'Remove file',
            icon: const Icon(Icons.clear),
            onPressed: onClear,
          ),
      ],
    );
  }
}
