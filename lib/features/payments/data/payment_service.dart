import 'package:supabase_flutter/supabase_flutter.dart';

enum PaymentProvider { gcashSim }

class PaymentsService {
  final SupabaseClient _sb;
  PaymentsService(this._sb);

  Future<String> upsertOnHoldSafe({
    required String rideId,
    required double amount,
    required String method, // e.g. 'gcash'
    required String payerUserId, // passenger
    required String payeeUserId, // driver
  }) async {
    // 1) look up existing
    final existing =
        await _sb
            .from('payment_intents')
            .select('id')
            .eq('ride_id', rideId)
            .maybeSingle();

    if (existing != null && existing['id'] != null) {
      final id = existing['id'] as String;

      // 2a) update existing -> on_hold
      final upd =
          await _sb
              .from('payment_intents')
              .update({
                'amount': amount,
                'method': method,
                'status': 'on_hold',
                'payer_user_id': payerUserId,
                'payee_user_id': payeeUserId,
              })
              .eq('id', id)
              .select('id')
              .maybeSingle();

      if (upd == null || upd['id'] == null) {
        throw 'Failed to update payment intent';
      }
      return upd['id'] as String;
    } else {
      // 2b) insert new -> on_hold
      final ins =
          await _sb
              .from('payment_intents')
              .insert({
                'ride_id': rideId,
                'amount': amount,
                'method': method,
                'status': 'on_hold',
                'payer_user_id': payerUserId,
                'payee_user_id': payeeUserId,
              })
              .select('id')
              .maybeSingle();

      if (ins == null || ins['id'] == null) {
        throw 'Failed to insert payment intent';
      }
      return ins['id'] as String;
    }
  }

  Future<void> captureForRide(String rideId) async {
    await _sb
        .from('payment_intents')
        .update({'status': 'captured'})
        .eq('ride_id', rideId);
  }

  Future<void> cancelForRide(String rideId) async {
    await _sb
        .from('payment_intents')
        .update({'status': 'canceled'})
        .eq('ride_id', rideId);
  }

  Future<Map<String, dynamic>?> getIntentForRide(String rideId) async {
    return await _sb
        .from('payment_intents')
        .select('id, ride_id, status, amount, method, created_at')
        .eq('ride_id', rideId)
        .maybeSingle();
  }
}
