import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../verify/data/verification_service.dart';

class VerifyIdentitySheet extends StatefulWidget {
  const VerifyIdentitySheet({super.key, required this.role});

  /// "driver" or "passenger"
  final String role;

  @override
  State<VerifyIdentitySheet> createState() => _VerifyIdentitySheetState();
}

class _VerifyIdentitySheetState extends State<VerifyIdentitySheet> {
  final picker = ImagePicker();
  late final VerificationService service;

  File? idFront, idBack, selfie, license, orcr;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    service = VerificationService(Supabase.instance.client);
  }

  Future<void> _pick(
    void Function(File) set, {
    ImageSource src = ImageSource.gallery,
  }) async {
    final x = await picker.pickImage(source: src, imageQuality: 85);
    if (x != null) set(File(x.path));
    setState(() {});
  }

  Future<void> _submit() async {
    setState(() => submitting = true);
    try {
      await service.submitOrUpdate(
        role: widget.role,
        idFront: idFront,
        idBack: idBack,
        selfie: selfie,
        driverLicense: widget.role == 'driver' ? license : null,
        orcr: widget.role == 'driver' ? orcr : null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Submitted for review')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => submitting = false);
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
              const SizedBox(height: 12),
              const Text('We only use these to keep riders and drivers safe.'),
              const SizedBox(height: 12),

              _pickerTile(
                'Government ID (front)',
                idFront,
                () => _pick((f) => idFront = f),
              ),
              _pickerTile(
                'Government ID (back)',
                idBack,
                () => _pick((f) => idBack = f),
              ),
              _pickerTile(
                'Selfie holding your ID',
                selfie,
                () => _pick((f) => selfie = f, src: ImageSource.camera),
              ),

              if (isDriver) ...[
                const Divider(),
                _pickerTile(
                  'Driver’s License',
                  license,
                  () => _pick((f) => license = f),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: submitting ? null : _submit,
                  child:
                      submitting
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

  Widget _pickerTile(String label, File? current, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle:
          current == null
              ? const Text('Tap to upload')
              : Text(current.path.split('/').last),
      trailing: const Icon(Icons.upload_file),
      onTap: onTap,
    );
  }
}
