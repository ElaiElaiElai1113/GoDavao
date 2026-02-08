import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../verify/data/verification_service.dart';
import 'package:godavao/common/app_colors.dart';

class VerifyIdentitySheet extends StatefulWidget {
  const VerifyIdentitySheet({super.key, required this.role});

  /// "driver" or "passenger"
  final String role;

  @override
  State<VerifyIdentitySheet> createState() => _VerifyIdentitySheetState();
}

class _VerifyIdentitySheetState extends State<VerifyIdentitySheet> {
  // Brand
  static const _purple = AppColors.purple;

  final _picker = ImagePicker();
  late final VerificationService _service;

  // Chosen images
  File? _idFront, _idBack, _selfie, _driverLicense;

  // Form
  bool _submitting = false;
  IdType? _selected;

  // 🇵🇭 Common PH IDs. Adjust requiresBack flags if needed.
  final List<IdType> _idTypes = const [
    IdType('Philippine Passport', requiresBack: false),
    IdType('PhilSys (National ID)', requiresBack: true),
    IdType('Driver’s License', requiresBack: true, isDriversLicense: true),
    IdType('SSS UMID', requiresBack: true),
    IdType('PRC ID', requiresBack: true),
    IdType('Postal ID', requiresBack: true),
    IdType('TIN ID', requiresBack: false),
    IdType('Voter’s ID', requiresBack: true),
    IdType('PWD ID', requiresBack: true),
    IdType('Senior Citizen ID', requiresBack: true),
    IdType('PhilHealth ID', requiresBack: true),
    IdType('Company/Student ID', requiresBack: true),
  ];

  @override
  void initState() {
    super.initState();
    _service = VerificationService(Supabase.instance.client);
  }

  // —————————————————— Image helpers ——————————————————

  Future<void> _chooseSource({
    required String title,
    required void Function(File) onPicked,
    bool preferFrontCamera = false,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      builder:
          (_) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Take photo'),
                  onTap: () async {
                    Navigator.pop(context);
                    final x = await _picker.pickImage(
                      source: ImageSource.camera,
                      preferredCameraDevice:
                          preferFrontCamera
                              ? CameraDevice.front
                              : CameraDevice.rear,
                      imageQuality: 88,
                    );
                    if (x != null) onPicked(File(x.path));
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from gallery'),
                  onTap: () async {
                    Navigator.pop(context);
                    final x = await _picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 88,
                    );
                    if (x != null) onPicked(File(x.path));
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
    );
  }

  Widget _imageTile({
    required String label,
    required File? file,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12.withValues(alpha: .08)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _purple.withValues(alpha: .12),
          child: Icon(
            file == null ? Icons.upload_file : Icons.image,
            color: _purple,
          ),
        ),
        title: Text(label, overflow: TextOverflow.ellipsis),
        subtitle:
            file == null
                ? const Text('Tap to add')
                : Text(
                  file.path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (file != null)
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(file == null ? 'Add' : 'Retake'),
            ),
          ],
        ),
      ),
    );
  }

  // —————————————————— Submission ——————————————————

  String? _validate() {
    if (_selected == null) return 'Please choose your ID type.';
    if (_idFront == null)
      return 'Please add the front photo of your ${_selected!.label}.';
    if (_selected!.requiresBack && _idBack == null) {
      return 'Please add the back photo of your ${_selected!.label}.';
    }
    if (_selfie == null) return 'Please add a selfie while holding your ID.';
    final isDriver = widget.role == 'driver';
    if (isDriver && !(_selected?.isDriversLicense ?? false)) {
      if (_driverLicense == null) return 'Please add your Driver’s License.';
    }
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.submitOrUpdate(
        role: widget.role,
        idType: _selected!.label,
        idFront: _idFront,
        idBack: _selected!.requiresBack ? _idBack : null,
        selfie: _selfie,

        driverLicense:
            widget.role == 'driver' && !(_selected?.isDriversLicense ?? false)
                ? _driverLicense
                : null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your verification documents have been submitted.\nPlease wait 1–3 business days for admin review before you can continue using all features.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.role == 'driver';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Verify your identity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('We only use these to keep riders and drivers safe.'),

              const SizedBox(height: 16),
              DropdownButtonFormField<IdType>(
                initialValue: _selected,
                decoration: const InputDecoration(
                  labelText: 'Select ID Type',
                  border: OutlineInputBorder(),
                ),
                items:
                    _idTypes
                        .map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(t.label)),
                        )
                        .toList(),
                onChanged:
                    (v) => setState(() {
                      _selected = v;
                      // Optional: clear back if new type doesn’t need it
                      if (!(v?.requiresBack ?? false)) _idBack = null;
                    }),
              ),

              const SizedBox(height: 14),
              _imageTile(
                label: 'ID (front)',
                file: _idFront,
                onPick:
                    () => _chooseSource(
                      title: 'ID (front)',
                      onPicked: (f) => _idFront = f,
                    ),
                onRemove: () => setState(() => _idFront = null),
              ),

              if (_selected?.requiresBack ?? false)
                _imageTile(
                  label: 'ID (back)',
                  file: _idBack,
                  onPick:
                      () => _chooseSource(
                        title: 'ID (back)',
                        onPicked: (f) => _idBack = f,
                      ),
                  onRemove: () => setState(() => _idBack = null),
                ),

              _imageTile(
                label: 'Selfie holding your ID',
                file: _selfie,
                onPick:
                    () => _chooseSource(
                      title: 'Selfie',
                      onPicked: (f) => _selfie = f,
                      preferFrontCamera: true,
                    ),
                onRemove: () => setState(() => _selfie = null),
              ),

              if (isDriver && !(_selected?.isDriversLicense ?? false)) ...[
                const Divider(height: 24),
                _imageTile(
                  label: 'Driver’s License',
                  file: _driverLicense,
                  onPick:
                      () => _chooseSource(
                        title: 'Driver’s License',
                        onPicked: (f) => _driverLicense = f,
                      ),
                  onRemove: () => setState(() => _driverLicense = null),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child:
                      _submitting
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Submit for Review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// —————————————————— Helper model ——————————————————
class IdType {
  final String label;
  final bool requiresBack;
  final bool isDriversLicense;
  const IdType(
    this.label, {
    this.requiresBack = true,
    this.isDriversLicense = false,
  });
}

