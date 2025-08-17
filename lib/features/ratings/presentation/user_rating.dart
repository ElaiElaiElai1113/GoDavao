// lib/features/ratings/presentation/user_rating.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserRatingBadge extends StatefulWidget {
  final String userId;
  final double iconSize;
  const UserRatingBadge({super.key, required this.userId, this.iconSize = 16});

  @override
  State<UserRatingBadge> createState() => _UserRatingBadgeState();
}

class _UserRatingBadgeState extends State<UserRatingBadge> {
  final supabase = Supabase.instance.client;
  double? _avg;
  int _count = 0;
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row =
          await supabase
              .from('ratings')
              .select('avg:avg(score), cnt:count(*)')
              .eq('ratee_user_id', widget.userId)
              .single();
      final m = Map<String, dynamic>.from(row as Map);
      setState(() {
        _avg = (m['avg'] as num?)?.toDouble();
        _count = (m['cnt'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_err != null) {
      // optional: show nothing on error
      return const SizedBox.shrink();
    }
    if (_avg == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border, size: widget.iconSize, color: Colors.amber),
          const SizedBox(width: 2),
          const Text('—'),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: widget.iconSize, color: Colors.amber),
        const SizedBox(width: 2),
        Text('${_avg!.toStringAsFixed(2)} (${_count})'),
      ],
    );
  }
}
