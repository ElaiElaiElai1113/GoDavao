import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/ratings_service.dart';

class RatingDetailsSheet extends StatefulWidget {
  final String userId;
  final String title;
  const RatingDetailsSheet({
    super.key,
    required this.userId,
    required this.title,
  });

  @override
  State<RatingDetailsSheet> createState() => _RatingDetailsSheetState();
}

class _RatingDetailsSheetState extends State<RatingDetailsSheet> {
  final supabase = Supabase.instance.client;
  Map<int, int>? _dist;
  List<Map<String, dynamic>> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = RatingsService(supabase);
    final d = await svc.fetchDistribution(widget.userId);
    final r = await svc.fetchRecentFeedback(widget.userId, limit: 30);
    if (!mounted) return;
    setState(() {
      _dist = d;
      _recent = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_dist != null) ...[
                        const Text('Rating breakdown'),
                        const SizedBox(height: 6),
                        ...[5, 4, 3, 2, 1].map((n) {
                          final v = _dist![n] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                SizedBox(width: 28, child: Text('$n★')),
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value:
                                        (_dist!.values.fold<int>(
                                                  0,
                                                  (a, b) => a + b,
                                                ) ==
                                                0)
                                            ? 0
                                            : v /
                                                _dist!.values
                                                    .fold<int>(
                                                      0,
                                                      (a, b) => a + b,
                                                    )
                                                    .toDouble(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('$v'),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],
                      const Text('Recent feedback'),
                      const SizedBox(height: 6),
                      ..._recent.map(
                        (e) => Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${e['score']}')),
                            title:
                                (e['tags'] is List &&
                                        (e['tags'] as List).isNotEmpty)
                                    ? Wrap(
                                      spacing: 6,
                                      children:
                                          (e['tags'] as List)
                                              .map<Widget>(
                                                (t) => Chip(label: Text('$t')),
                                              )
                                              .toList(),
                                    )
                                    : const SizedBox.shrink(),
                            subtitle: Text((e['comment'] ?? '') as String),
                            trailing: Text(
                              (e['created_at'] ?? '').toString().substring(
                                0,
                                10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
