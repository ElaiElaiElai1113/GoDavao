import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/sos_service.dart';

class SosSheet extends StatefulWidget {
  final String? rideId;
  const SosSheet({super.key, this.rideId});

  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet> {
  late final SosService _sos;
  bool _sending = false;
  final _fln = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _sos = SosService(Supabase.instance.client);
    _fln.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  Future<void> _confirmNotif() async {
    await _fln.show(
      1001,
      'SOS Sent',
      'We notified your trusted contacts with your live location.',
      const NotificationDetails(
        android: AndroidNotificationDetails('safety', 'Safety'),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _sendSOS() async {
    setState(() => _sending = true);
    try {
      await _sos.triggerSOS(rideId: widget.rideId, notifyContacts: true);
      await _confirmNotif();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS sent. Stay safe—we’re on it.')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send SOS: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _callHotline(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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
              'Share your live location with trusted contacts or call local emergency services.',
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sending ? null : _sendSOS,
              icon: const Icon(Icons.warning),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size.fromHeight(48),
              ),
              label: Text(
                _sending ? 'Sending SOS…' : 'Send SOS to Trusted Contacts',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _callHotline('911'),
              icon: const Icon(Icons.call),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              label: const Text('Call 911'),
            ),
            const SizedBox(height: 8),
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
