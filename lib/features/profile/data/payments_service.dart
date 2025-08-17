// lib/features/payments/data/payments_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Simulated providers supported by the backend SQL
class PaymentProvider {
  static const gcashSim = 'gcash_sim';
  static const paymongoSim = 'paymongo_sim';
}

class PaymentsService {
  PaymentsService(this._sb);
  final SupabaseClient _sb;

  /// Create (or reuse) a pre-capture payment hold for this ride.
  /// Returns the payment_id (UUID).
  ///
  /// provider: PaymentProvider.gcashSim | PaymentProvider.paymongoSim
  Future<String> confirmAndHold({
    required String rideId,
    required String provider,
  }) async {
    // Idempotency: reuse active pre-capture payment if present
    final existing =
        await _sb
            .from('payments')
            .select('id,status,provider')
            .eq('ride_id', rideId)
            .maybeSingle();

    if (existing == null) {
      final res = await _sb.rpc(
        'rpc_create_hold',
        params: {
          'p_ride_id': rideId,
          'p_provider': provider,
          'p_capture_method': 'manual',
        },
      );
      return res as String; // payment_id
    }
    return existing['id'] as String;
  }

  /// For paymongo_sim only — call this after your mock "payment sheet" succeeds.
  Future<void> simulatePaymongoSheetSuccess(String paymentId) async {
    await _sb.rpc(
      'rpc_simulate_paymongo_webhook',
      params: {'p_payment_id': paymentId},
    );
  }

  /// Mark the ride completed and capture the held payment (if capturable).
  /// Safe to call once on completion button.
  Future<void> completeRideAndCapture(String rideId) async {
    // 1) Complete the ride
    await _sb
        .from('ride_matches')
        .update({'status': 'completed'})
        .eq('id', rideId);

    // 2) Capture if payment is capturable
    final p =
        await _sb
            .from('payments')
            .select('id,status')
            .eq('ride_id', rideId)
            .maybeSingle();

    if (p != null && p['status'] == 'requires_capture') {
      await _sb.rpc('rpc_capture_payment', params: {'p_payment_id': p['id']});
    }
  }

  /// Cancel the ride and void any pending pre-capture payment.
  Future<void> cancelRideAndVoid(String rideId) async {
    await _sb
        .from('ride_matches')
        .update({'status': 'canceled'})
        .eq('id', rideId);

    final p =
        await _sb
            .from('payments')
            .select('id,status')
            .eq('ride_id', rideId)
            .maybeSingle();

    if (p != null &&
        (p['status'] == 'requires_capture' ||
            p['status'] == 'requires_payment_method')) {
      await _sb.rpc('rpc_void_payment', params: {'p_payment_id': p['id']});
    }
  }

  /// Stream the single payment row for a ride (or null if none).
  Stream<Map<String, dynamic>?> watchPayment(String rideId) {
    return _sb
        .from('payments')
        .stream(primaryKey: ['id'])
        .eq('ride_id', rideId)
        .map((rows) => rows.isNotEmpty ? rows.first : null);
  }

  /// Stream the wallet row for a user (GCash sim balance + holds).
  Stream<Map<String, dynamic>?> watchWallet(String userId) {
    return _sb
        .from('wallets')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) => rows.isNotEmpty ? rows.first : null);
  }

  /// Optional helper: friendly error mapping for SnackBars/Toasts.
  static String mapPaymentError(Object e) {
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
