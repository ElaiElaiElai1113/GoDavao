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
            Text(
              'Choose payment method',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: Text(
                'GCash',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: Text(
                'Upload proof and weâ€™ll hold the payment',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              onTap: () => Navigator.pop(context, PaymentChoice('gcash')),
            ),
            ListTile(
              leading: const Icon(Icons.payments),
              title: Text(
                'Cash',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: Text(
                'Pay your driver in cash on arrival',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              onTap: () => Navigator.pop(context, PaymentChoice('cash')),
            ),
          ],
        ),
      ),
    );
  }
}
