import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerifiedBadge extends StatefulWidget {
  final String userId;
  final double size;
  const VerifiedBadge({super.key, required this.userId, this.size = 16});

  @override
  State<VerifiedBadge> createState() => _VerifiedBadgeState();
}

class _VerifiedBadgeState extends State<VerifiedBadge> {
  final supabase = Supabase.instance.client;
  bool _isVerified = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row =
          await supabase
              .from('users')
              .select('verified')
              .eq('id', widget.userId)
              .maybeSingle();
      setState(() {
        _isVerified = ((row as Map?)?['verified'] == true);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_isVerified) return const SizedBox.shrink();
    return Tooltip(
      message: 'Verified',
      child: Icon(Icons.verified, color: Colors.teal, size: widget.size),
    );
  }
}
