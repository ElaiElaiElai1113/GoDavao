import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SosSheet extends StatefulWidget {
  final String? rideId;
  const SosSheet({super.key, this.rideId});

  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet> {
  final _sb = Supabase.instance.client;
  bool _sending = false;
  List<String> _numbers = [];

  @override
  void initState() {
    super.initState();
    _loadTrustedContacts();
  }

  Future<void> _loadTrustedContacts() async {
    try {
      final userId = _sb.auth.currentUser?.id;
      final rows = await _sb
          .from('trusted_contacts')
          .select('phone')
          .eq('user_id', userId as Object);

      setState(() {
        _numbers = rows.map<String>((r) => r['phone'].toString()).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load contacts: $e')));
    }
  }

  Future<void> _sendSOS() async {
    if (_numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trusted contacts found.')),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      // 1️⃣ Get location
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final mapsLink =
          'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
      final message =
          '🚨 SOS ALERT: I may be in danger. Please check my location: $mapsLink';

      // 2️⃣ Open system SMS composer
      final separator = Platform.isIOS ? ',' : ';';
      final recipients = _numbers.join(separator);
      final uri = Uri(
        scheme: 'sms',
        path: recipients,
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening SMS composer...')),
        );
      } else {
        throw Exception('Could not open SMS composer');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send SOS: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Safety Center',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Send your live location to trusted contacts via SMS.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sending ? null : _sendSOS,
              icon: const Icon(Icons.warning),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size.fromHeight(48),
              ),
              label: Text(_sending ? 'Preparing SOS…' : 'Send SOS via SMS'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed:
                  () => Navigator.of(context).pushNamed('/trusted-contacts'),
              child: const Text('Manage Trusted Contacts'),
            ),
          ],
        ),
      ),
    );
  }
}
