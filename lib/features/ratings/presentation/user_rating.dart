import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/ratings_service.dart';
import 'rating_badge.dart';

/// Fetches a user's aggregate rating then shows RatingBadge
class UserRatingBadge extends StatefulWidget {
  final String userId;
  final double iconSize;
  final TextStyle? textStyle;
  final bool dense;

  const UserRatingBadge({
    super.key,
    required this.userId,
    this.iconSize = 14,
    this.textStyle,
    this.dense = true,
  });

  @override
  State<UserRatingBadge> createState() => _UserRatingBadgeState();
}

class _UserRatingBadgeState extends State<UserRatingBadge> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _agg;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final agg = await RatingsService(
        supabase,
      ).fetchUserAggregate(widget.userId);
      if (!mounted) return;
      setState(() {
        _agg = agg;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: widget.iconSize + 2,
        child: const AspectRatio(
          aspectRatio: 3.5,
          child: LinearProgressIndicator(),
        ),
      );
    }

    final avg = (_agg?['avg_rating'] as num?)?.toDouble();
    final cnt = (_agg?['rating_count'] as int?) ?? 0;

    return RatingBadge(
      avg: avg,
      count: cnt,
      iconSize: widget.iconSize,
      textStyle: widget.textStyle,
      dense: widget.dense,
    );
  }
}
