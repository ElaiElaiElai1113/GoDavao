import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/safety_service.dart';

class SosSheet extends StatefulWidget {
  final String rideId;
  const SosSheet({super.key, required this.rideId});

  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet> {
  final supabase = Supabase.instance.client;
  Position? _pos;
  bool _loading = true;
  List<Map<String, dynamic>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        throw 'Location permission denied permanently';
      }
      _pos = await Geolocator.getCurrentPosition();
      _contacts = await SafetyService(supabase).listContacts();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _mapsLink() {
    final lat = _pos?.latitude, lng = _pos?.longitude;
    if (lat == null || lng == null) return '';
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  Future<void> _call911() async {
    final uri = Uri.parse('tel:911');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _textFirstContact() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No trusted contacts yet.')));
      return;
    }
    final c = _contacts.firstWhere(
      (c) =>
          (c['notify_by_sms'] ?? true) &&
          (c['phone'] ?? '').toString().isNotEmpty,
      orElse: () => {},
    );
    final phone = c['phone']?.toString();
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No SMS-enabled contact found.')),
      );
      return;
    }
    final body = Uri.encodeComponent(
      'SOS! Please help. My location: ${_mapsLink()}',
    );
    final scheme =
        Platform.isIOS ? 'sms:$phone&body=$body' : 'sms:$phone?body=$body';
    final uri = Uri.parse(scheme);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _logInAppAlert() async {
    final lat = _pos?.latitude, lng = _pos?.longitude;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Location unavailable')));
      return;
    }
    await SafetyService(supabase).logSOS(
      rideId: widget.rideId,
      lat: lat,
      lng: lng,
      message: 'In-app SOS triggered',
    );
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('In-app alert sent')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                  mainAxisSize: MainAxisSize.min,
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
                      'Emergency',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.local_phone, color: Colors.red),
                      title: const Text('Call 911'),
                      subtitle: const Text(
                        'Connect to local emergency hotline',
                      ),
                      onTap: _call911,
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.sms_failed,
                        color: Colors.orange,
                      ),
                      title: const Text('Text trusted contact'),
                      subtitle: Text(
                        _contacts.isEmpty
                            ? 'No contacts configured'
                            : 'Send your live location',
                      ),
                      onTap: _textFirstContact,
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.report_gmailerrorred,
                        color: Colors.blue,
                      ),
                      title: const Text('Send in-app alert'),
                      subtitle: Text(
                        _pos == null ? 'Location unavailable yet' : _mapsLink(),
                      ),
                      onTap: _logInAppAlert,
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
      ),
    );
  }
}
