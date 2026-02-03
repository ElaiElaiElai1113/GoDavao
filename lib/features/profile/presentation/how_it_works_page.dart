// lib/features/profile/presentation/how_it_works_page.dart
import 'package:flutter/material.dart';
import 'package:godavao/features/dashboard/presentation/dashboard_page.dart';

class HowItWorksPage extends StatelessWidget {
  const HowItWorksPage({super.key});

  static const _purple = Color(0xFF6A27F7);
  static const _purpleDark = Color(0xFF4B18C9);
  static const _textDim = Color(0xFF667085);

  @override
  Widget build(BuildContext context) {
    final steps = <_StepInfo>[
      _StepInfo(
        icon: Icons.verified_user_outlined,
        title: 'Create your account & verify',
        desc:
            'Sign up with your email. Add your name and phone. Get verified to build trust between passengers and drivers.',
      ),
      _StepInfo(
        icon: Icons.my_location_outlined,
        title: 'Set pickup & destination',
        desc:
            'On the Dashboard, pin your pickup and destination. You’ll see a route preview and the estimated fare.',
      ),
      _StepInfo(
        icon: Icons.directions_car_filled_outlined,
        title: 'Request & get matched',
        desc:
            'Tap “Request Ride.” Our matcher finds drivers on similar routes. You’ll be notified when a driver accepts.',
      ),
      _StepInfo(
        icon: Icons.map_outlined,
        title: 'Track in real time',
        desc:
            'Watch your driver’s live location on the map. You can chat in-app if you need to coordinate pickup.',
      ),
      _StepInfo(
        icon: Icons.payments_outlined,
        title: 'Ride, pay, and rate',
        desc:
            'Enjoy your ride. Pay per your chosen method, then rate to help keep the community safe and reliable.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('How it works'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_purple.withValues(alpha: 0.06), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _hero(),
            const SizedBox(height: 12),
            const Text(
              'GoDavao makes carpooling simple and safe. Here’s the journey from request to drop-off:',
              style: TextStyle(color: _textDim, height: 1.35),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < steps.length; i++)
              _StepCard(index: i + 1, info: steps[i]),
            const SizedBox(height: 8),
            _tipTile(
              icon: Icons.info_outline,
              title: 'Pro tip',
              text:
                  'Complete your profile and get verified to increase your match success and build trust with the community.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [_purple, _purpleDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const DashboardPage()),
                    );
                  },
                  icon: const Icon(
                    Icons.dashboard_customize_outlined,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Start using GoDavao',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF2EEFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.rocket_launch_outlined, color: _purpleDark),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Welcome to GoDavao! Find a ride that fits your route, save money, and reduce traffic—together.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipTile({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _purpleDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: _textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepInfo {
  final IconData icon;
  final String title;
  final String desc;
  const _StepInfo({
    required this.icon,
    required this.title,
    required this.desc,
  });
}

class _StepCard extends StatelessWidget {
  final int index;
  final _StepInfo info;
  const _StepCard({required this.index, required this.info});

  static const _purple = Color(0xFF6A27F7);
  static const _textDim = Color(0xFF667085);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _purple,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Icon + text
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(info.icon, color: _purple),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.desc,
                        style: const TextStyle(color: _textDim, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
