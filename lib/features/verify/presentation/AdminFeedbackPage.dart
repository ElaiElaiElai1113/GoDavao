import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

String formatWhen(dynamic isoString) {
  if (isoString == null) return '';
  final dt = DateTime.parse(isoString.toString()).toLocal();
  return DateFormat('MMM d, y • h:mm a').format(dt);
}

class AdminFeedbackPage extends StatefulWidget {
  const AdminFeedbackPage({super.key});

  @override
  State<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends State<AdminFeedbackPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _ratings = [];

  @override
  void initState() {
    super.initState();
    _fetchRatings();
  }

  Future<void> _fetchRatings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1: Fetch all ratings
      final ratingsResponse = await _sb
          .from('ratings')
          .select('score, comment, ratee_user_id, created_at')
          .order('created_at', ascending: false);

      // Step 2: Enrich each rating with the user name
      List<Map<String, dynamic>> enriched = [];

      for (final rating in ratingsResponse) {
        final userId = rating['ratee_user_id'];
        String name = 'Unknown User';

        if (userId != null) {
          final userResp =
              await _sb
                  .from('users')
                  .select('name')
                  .eq('id', userId)
                  .maybeSingle();

          if (userResp != null && userResp['name'] != null) {
            name = userResp['name'];
          }
        }

        enriched.add({...rating, 'user_name': name});
      }

      setState(() {
        _ratings = enriched;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load feedback: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Feedback & Ratings'),
        backgroundColor: const Color(0xFF6A27F7),
        foregroundColor: Colors.white,
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                onRefresh: _fetchRatings,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ratings.length,
                  itemBuilder: (context, i) {
                    final rating = _ratings[i];
                    final userName = rating['user_name'] ?? 'Unknown User';
                    final score = (rating['score'] ?? 0).toInt();
                    final comment = rating['comment'] ?? '';
                    final when = rating['created_at'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                color: Color(0xFF6A27F7),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            5,
            (index) => Icon(
              index < score ? Icons.star : Icons.star_border,
              color: Colors.amber,
              size: 18,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatWhen(when),                // ⬅️ formatted timestamp
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    ),
  ],
),
                          const SizedBox(height: 8),
                          Text(
                            comment.isNotEmpty
                                ? comment
                                : '(No comment provided)',
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
    );
  }
}
