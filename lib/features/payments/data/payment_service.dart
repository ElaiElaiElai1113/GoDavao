// lib/features/payments/data/payments_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supported simulated providers on the backend.
class PaymentProvider {
  static const gcashSim =
      'gcash_sim'; // in-app wallet (hold now, capture later)
  static const paymongoSim = 'paymongo_sim'; // card intent (manual capture)
}

/// Grab/Uber-style service:
/// - Place a HOLD against the ride MATCH
/// - Server triggers capture/void automatically when the ride completes/cancels
class PaymentsService {
  PaymentsService(this._sb);
  final SupabaseClient _sb;

  /// Idempotently place a pre-capture HOLD for a given ride match.
  ///
  /// Defaults to GCash sim for an automatic, receipt-free experience.
  /// Returns the payment_id (UUID).
  Future<String> holdForMatch({
    required String matchId,
    String provider = PaymentProvider.gcashSim,
  }) async {
    // Reuse an existing pre-capture payment if one already exists.
    final existing =
        await _sb
            .from('payments')
            .select('id,status,provider')
            .eq('ride_id', matchId)
            // NOTE: Use .filter('in', ...) to avoid Dart keyword conflicts and SDK differences
            .filter(
              'status',
              'in',
              '("requires_payment_method","requires_capture")',
            )
            .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    // Create the hold via RPC
    final res = await _sb.rpc(
      'rpc_create_hold',
      params: {
        'p_ride_id': matchId,
        'p_provider': provider,
        'p_capture_method': 'manual',
      },
    );

    // If you ever use paymongo_sim and show a sheet, you'll want to call:
    // await simulatePaymongoSheetSuccess(paymentId);
    return res as String;
  }

  /// OPTIONAL: If using PayMongo sim and your mock sheet "succeeds",
  /// call this to flip the payment into `requires_capture`.
  Future<void> simulatePaymongoSheetSuccess(String paymentId) async {
    await _sb.rpc(
      'rpc_simulate_paymongo_webhook',
      params: {'p_payment_id': paymentId},
    );
  }

  /// Mark the ride as COMPLETED.
  ///
  /// With the recommended DB trigger installed, this *automatically captures*
  /// any `requires_capture` payment for the match:
  /// - GCash sim: moves passenger hold → driver pending_payout
  /// - PayMongo sim: credits driver pending_payout
  Future<void> markRideCompleted(String matchId) async {
    await _sb
        .from('ride_matches')
        .update({'status': 'completed'})
        .eq('id', matchId);
    // No need to call rpc_capture_payment; the trigger handles it.
  }

  /// Mark the ride as CANCELED.
  ///
  /// With the recommended DB trigger installed, this *automatically voids*
  /// any pre-capture payment for the match:
  /// - GCash sim: releases passenger hold back to available
  /// - PayMongo sim: switches payment to `canceled`
  Future<void> markRideCanceled(String matchId) async {
    await _sb
        .from('ride_matches')
        .update({'status': 'canceled'})
        .eq('id', matchId);
    // No need to call rpc_void_payment; the trigger handles it.
  }

  /// Get the active (or latest) payment row for a ride match.
  Future<Map<String, dynamic>?> getPaymentForMatch(String matchId) async {
    final row =
        await _sb
            .from('payments')
            .select()
            .eq('ride_id', matchId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
    return row;
  }

  /// Stream a ride's payment row in realtime (null if none yet).
  Stream<Map<String, dynamic>?> watchPayment(String matchId) {
    return _sb
        .from('payments')
        .stream(primaryKey: ['id'])
        .eq('ride_id', matchId)
        .map((rows) => rows.isNotEmpty ? rows.first : null);
  }

  /// Stream a user's wallet (GCash sim balance/holds/pending payout).
  Stream<Map<String, dynamic>?> watchWallet(String userId) {
    return _sb
        .from('wallets')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) => rows.isNotEmpty ? rows.first : null);
  }

  /// Convenience labels for UI based on `payments.status`.
  static String statusLabel(String? status) {
    switch (status) {
      case 'requires_payment_method':
        return 'Awaiting payment method';
      case 'requires_capture':
        return 'Fare is on hold';
      case 'succeeded':
        return 'Payment captured';
      case 'canceled':
        return 'Hold released';
      case 'failed':
        return 'Payment failed';
      default:
        return '';
    }
  }

  /// Friendly error mapping for SnackBars/Toasts.
  static String mapError(Object e) {
    final s = e.toString();
    if (s.contains('insufficient funds'))
      return 'Insufficient wallet balance to place the hold.';
    if (s.contains('ride not in a payable state'))
      return 'Wait until the driver accepts the ride.';
    if (s.contains('payment not capturable'))
      return 'Payment isn’t ready to capture yet.';
    if (s.contains('payment not voidable'))
      return 'Payment can’t be voided in its current state.';
    if (s.contains('cannot void after completion'))
      return 'Ride already completed; cannot void.';
    if (s.contains('not authenticated')) return 'Please log in again.';
    if (s.contains('not authorized'))
      return 'Only the ride’s passenger or driver can perform this.';
    return 'Something went wrong. Please try again.';
  }
}
