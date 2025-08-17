import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../verify/data/verification_service.dart';

class VerifyIdentitySheet extends StatefulWidget {
  const VerifyIdentitySheet({super.key});

  @override
  State<VerifyIdentitySheet> createState() => _VerifyIdentitySheetState();
}

class _VerifyIdentitySheetState extends State<VerifyIdentitySheet> {
  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  XFile? _selfie;
  XFile? _front;
  XFile? _back;
  bool _submitting = false;

  Future<void> _pick(Function(XFile) assign, {required bool fromCamera}) async {
    final x =
        await (fromCamera
            ? picker.pickImage(source: ImageSource.camera, imageQuality: 85)
            : picker.pickImage(source: ImageSource.gallery, imageQuality: 85));
    if (x != null) setState(() => assign(x));
  }

  Future<void> _submit() async {
    if (_selfie == null || _front == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selfie and ID front are required.')),
      );
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await VerificationService(supabase).submitRequest(
        selfiePath: _selfie!.path,
        idFrontPath: _front!.path,
        idBackPath: _back?.path,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification submitted.')));
    } catch (e) {
      final msg = (e is PostgrestException) ? e.message : e.toString();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Submit failed: $msg')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _slot(String label, XFile? file, void Function(XFile) setFile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  image:
                      file == null
                          ? null
                          : DecorationImage(
                            image: FileImage(File(file.path)),
                            fit: BoxFit.cover,
                          ),
                ),
                child:
                    file == null
                        ? const Center(child: Text('No image'))
                        : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                  onPressed: () => _pick(setFile, fromCamera: true),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  onPressed: () => _pick(setFile, fromCamera: false),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Verify your identity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _slot('Selfie holding your ID', _selfie, (x) => _selfie = x),
              const SizedBox(height: 12),
              _slot('Government ID (front)', _front, (x) => _front = x),
              const SizedBox(height: 12),
              _slot('Government ID (back) — optional', _back, (x) => _back = x),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon:
                      _submitting
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.verified_user),
                  label: Text(
                    _submitting ? 'Submitting…' : 'Submit for review',
                  ),
                  onPressed: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
