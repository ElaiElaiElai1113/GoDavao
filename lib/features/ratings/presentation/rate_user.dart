import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/ratings_service.dart';

class RateUserSheet extends StatefulWidget {
  final String rideId;
  final String raterUserId;
  final String rateeUserId;
  final String rateeName;
  final String rateeRole; // 'driver' | 'passenger'

  const RateUserSheet({
    super.key,
    required this.rideId,
    required this.raterUserId,
    required this.rateeUserId,
    required this.rateeName,
    required this.rateeRole,
  });

  @override
  State<RateUserSheet> createState() => _RateUserSheetState();
}

class _RateUserSheetState extends State<RateUserSheet> {
  final supabase = Supabase.instance.client;
  int _rating = 5;
  final _comment = TextEditingController();
  final Set<String> _selected = {};

  List<String> get _positiveTags =>
      widget.rateeRole == 'driver'
          ? const [
            'Safe driving',
            'On-time',
            'Friendly',
            'Clean vehicle',
            'Good navigation',
          ]
          : const [
            'On-time',
            'Courteous',
            'Clear pickup',
            'Good communication',
          ];

  List<String> get _negativeTags =>
      widget.rateeRole == 'driver'
          ? const [
            'Reckless',
            'Late',
            'Rude',
            'Unclean vehicle',
            'Route issues',
          ]
          : const [
            'Late',
            'No-show',
            'Rude',
            'Incorrect pickup',
            'Payment issue',
          ];

  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await RatingsService(supabase).submitRating(
        rideId: widget.rideId,
        raterUserId: widget.raterUserId,
        rateeUserId: widget.rateeUserId,
        rateeRole: widget.rateeRole,
        rating: _rating,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        tags: _selected.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback!')),
      );
    } catch (e) {
      final msg = e is PostgrestException ? e.message : e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit rating: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Padding tagChip(String label, {bool negative = false}) => Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: FilterChip(
        label: Text(label),
        selected: _selected.contains(label),
        onSelected:
            (sel) => setState(() {
              if (sel) {
                _selected.add(label);
              } else {
                _selected.remove(label);
              }
            }),
        selectedColor: negative ? Colors.red.shade100 : Colors.green.shade100,
      ),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Rate ${widget.rateeName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Stars
Row(
  children: List.generate(5, (i) {
    final idx = i + 1;
    final filled = idx <= _rating;
    final color = filled ? Colors.amber.shade700 : Colors.grey.shade400;

    return IconButton(
      onPressed: () => setState(() => _rating = idx),
      icon: Icon(
        filled ? Icons.star : Icons.star_border,
        size: 30,
        color: color,
      ),
      style: IconButton.styleFrom(foregroundColor: color),
    );
  }),
),


              const SizedBox(height: 8),
              Text(
                'What stood out?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Wrap(children: _positiveTags.map((t) => tagChip(t)).toList()),
              Wrap(
                children:
                    _negativeTags
                        .map((t) => tagChip(t, negative: true))
                        .toList(),
              ),

              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional comment',
                  hintText: 'Share more details…',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon:
                      _submitting
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.send),
                  label: Text(_submitting ? 'Submitting…' : 'Submit'),
                  onPressed: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
