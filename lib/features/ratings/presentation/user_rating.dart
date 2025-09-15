// lib/features/ratings/presentation/user_rating.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserRatingBadge extends StatefulWidget {
  final String userId;
  final double iconSize;
  final bool listenRealtime; // set to false if you don't want live updates

  const UserRatingBadge({
    super.key,
    required this.userId,
    this.iconSize = 16,
    this.listenRealtime = true,
  });

  @override
  State<UserRatingBadge> createState() => _UserRatingBadgeState();
}

class _UserRatingBadgeState extends State<UserRatingBadge> {
  final supabase = Supabase.instance.client;

  double? _avg;
  int _count = 0;
  bool _loading = true;
  String? _err;

  RealtimeChannel? _channel;
  bool _disposed = false;
  Timer? _debounce;

  bool get _mountedSafe => mounted && !_disposed;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.listenRealtime) {
      _subscribe();
    }
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final row =
          await supabase
              .from('ratings')
              .select('avg:avg(score), cnt:count(*)')
              .eq('ratee_user_id', widget.userId)
              .maybeSingle();

      final m = _asMap(row);
      final nextAvg = (m?['avg'] as num?)?.toDouble();
      final nextCnt = (m?['cnt'] as num?)?.toInt() ?? 0;

      if (!_mountedSafe) {
        return;
      }
      // Avoid unnecessary rebuilds
      if (_avg == nextAvg &&
          _count == nextCnt &&
          _loading == false &&
          _err == null) {
        return;
      }

      setState(() {
        _avg = nextAvg;
        _count = nextCnt;
        _loading = false;
        _err = null;
      });
    } catch (e) {
      if (!_mountedSafe) {
        return;
      }
      setState(() {
        _err = e is PostgrestException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  void _subscribe() {
    // Build one channel and attach three listeners (insert/update/delete) with the REQUIRED named args.
    final ch = supabase.channel('ratings_user_${widget.userId}');

    void add(PostgresChangeEvent evt) {
      ch.onPostgresChanges(
        event: evt,
        schema: 'public',
        table: 'ratings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, // REQUIRED
          column: 'ratee_user_id', // REQUIRED
          value: widget.userId, // REQUIRED
        ),
        callback: (_) => _scheduleReload(),
      );
    }

    add(PostgresChangeEvent.insert);
    add(PostgresChangeEvent.update);
    add(PostgresChangeEvent.delete);

    _channel = ch.subscribe();
  }

  void _scheduleReload() {
    if (!_mountedSafe) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (_mountedSafe) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    if (_err != null) {
      // Quietly render nothing on error (you can swap in an icon if you want)
      return const SizedBox.shrink();
    }

    const iconColor = Colors.amber;

    if (_avg == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border, size: widget.iconSize, color: iconColor),
          const SizedBox(width: 2),
          const Text('—'),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: widget.iconSize, color: iconColor),
        const SizedBox(width: 2),
        Text('${_avg!.toStringAsFixed(2)} ($_count)'),
      ],
    );
  }
}
