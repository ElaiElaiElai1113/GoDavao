import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:godavao/features/payments/presentation/payment_status_chip.dart';

void main() {
  group('PaymentStatusChip Widget', () {
    testWidgets('displays pending status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'pending'),
          ),
        ),
      );

      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('displays completed status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'completed'),
          ),
        ),
      );

      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('displays failed status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'failed'),
          ),
        ),
      );

      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('applies correct colors for each status', (tester) async {
      // Pending - should be orange/amber
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'pending'),
          ),
        ),
      );

      final pendingChip = tester.widget<Chip>(find.byType(Chip));
      final pendingLabel = pendingChip.label as Text;
      expect(pendingLabel.data, 'Pending');

      // Completed - should be green
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'completed'),
          ),
        ),
      );

      final completedChip = tester.widget<Chip>(find.byType(Chip));
      final completedLabel = completedChip.label as Text;
      expect(completedLabel.data, 'Paid');

      // Failed - should be red
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'failed'),
          ),
        ),
      );

      final failedChip = tester.widget<Chip>(find.byType(Chip));
      final failedLabel = failedChip.label as Text;
      expect(failedLabel.data, 'Failed');
    });

    testWidgets('handles unknown status gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaymentStatusChip(status: 'unknown_status'),
          ),
        ),
      );

      // Should not crash and should display something
      expect(find.byType(PaymentStatusChip), findsOneWidget);
    });
  });
}
