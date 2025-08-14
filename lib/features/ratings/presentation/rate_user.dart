import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/ratings_service.dart';
import './star_ratings.dart';

class RateUserSheet extends StatefulWidget {
  final String rideId;
  final String raterUserId;
  final String rateeUserId;
  final String rateeName;
  final String rateeRole;
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
  late final RatingsService _ratings;
  int _score = 5;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  Map<String, dynamic>? _existing;

  @override
  void initState() {
    super.initState();
    _ratings = RatingsService(Supabase.instance.client);
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final ex = await _ratings.getExistingRating(
      rideId: widget.rideId,
      raterUserId: widget.raterUserId,
      rateeUserId: widget.rateeUserId,
    );
    if (mounted) setState(() => _existing = ex);
    if (ex != null) {
      _score = (ex['score'] as int?) ?? 5;
      _commentCtrl.text = (ex['comment'] as String?) ?? '';
    }
  }

  Future<void> _submit() async {
    if (_existing != null) {
      // Already rated; just close
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _ratings.submitRating(
        rideId: widget.rideId,
        raterUserId: widget.raterUserId,
        rateeUserId: widget.rateeUserId,
        rateeRole: widget.rateeRole,
        score: _score,
        comment:
            _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit rating: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final already = _existing != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 48,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              already
                  ? 'You rated ${widget.rateeName}'
                  : 'Rate ${widget.rateeName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            StarRating(
              value: _score,
              onChanged: already ? null : (v) => setState(() => _score = v),
              size: 32,
              readOnly: already,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentCtrl,
              enabled: !already,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Optional comment',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(already ? 'Close' : 'Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
