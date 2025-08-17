import 'package:flutter/material.dart';

class PaymentChoice {
  final String method; // 'gcash' or 'cash'
  PaymentChoice(this.method);
}

class PaymentMethodSheet extends StatelessWidget {
  const PaymentMethodSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Choose payment method',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('GCash'),
              subtitle: const Text('Upload proof and we’ll hold the payment'),
              onTap: () => Navigator.pop(context, PaymentChoice('gcash')),
            ),
            ListTile(
              leading: const Icon(Icons.payments),
              title: const Text('Cash'),
              subtitle: const Text('Pay your driver in cash on arrival'),
              onTap: () => Navigator.pop(context, PaymentChoice('cash')),
            ),
          ],
        ),
      ),
    );
  }
}
