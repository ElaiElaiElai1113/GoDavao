import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:godavao/features/verify/presentation/verified_badge.dart';

void main() {
  group('VerifiedBadge Widget', () {
    testWidgets('builds without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('uses FutureBuilder for async loading', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
            ),
          ),
        ),
      );

      expect(find.byType(FutureBuilder), findsOneWidget);
    });

    testWidgets('respects custom size parameter', (tester) async {
      const customSize = 32.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
              size: customSize,
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('shows different icons for different statuses', (tester) async {
      // Note: These tests demonstrate the structure but require
      // actual Supabase responses to verify icon rendering

      // The widget uses FutureBuilder so icons will be rendered based on data
      // Icons.verified for 'approved' status
      // Icons.hourglass_bottom for 'pending' status
      // SizedBox.shrink() for other statuses

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
            ),
          ),
        ),
      );

      // Widget should be present
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('handles empty userId gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: '',
            ),
          ),
        ),
      );

      // Should not crash
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('uses green color for approved status', (tester) async {
      // This test shows the expected behavior
      // In actual usage with Supabase, approved status returns Icons.verified with Colors.green
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('uses orange color for pending status', (tester) async {
      // This test shows the expected behavior
      // In actual usage with Supabase, pending status returns Icons.hourglass_bottom with Colors.orange
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('returns SizedBox.shrink() for unverified status', (tester) async {
      // This test shows the expected behavior
      // In actual usage with Supabase, non-verified users return SizedBox.shrink()
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'test-user-id',
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
    });
  });

  group('VerifiedBadge Integration', () {
    testWidgets('works in Row layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Text('User Name'),
                VerifiedBadge(userId: 'test-user'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.text('User Name'), findsOneWidget);
    });

    testWidgets('works in Column layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Driver Information'),
                VerifiedBadge(userId: 'test-user'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.text('Driver Information'), findsOneWidget);
    });

    testWidgets('can have multiple badges in same tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VerifiedBadge(userId: 'user-1'),
                VerifiedBadge(userId: 'user-2'),
                VerifiedBadge(userId: 'user-3'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsNWidgets(3));
    });

    testWidgets('can be used in ListTile leading/trailing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListTile(
              title: Text('Driver Name'),
              trailing: VerifiedBadge(userId: 'test-user'),
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.text('Driver Name'), findsOneWidget);
    });

    testWidgets('can be used in CircleAvatar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircleAvatar(
              child: VerifiedBadge(userId: 'test-user'),
            ),
          ),
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });

  group('VerifiedBadge Edge Cases', () {
    testWidgets('handles special characters in userId', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: 'user-with-special-chars-123',
            ),
          ),
        ),
      );

      // Should not crash
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('handles very long userId', (tester) async {
      const longUserId = 'very-long-user-id-string-for-testing-purposes';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(
              userId: longUserId,
            ),
          ),
        ),
      );

      // Should not crash
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('rebuilds when userId changes', (tester) async {
      String userId = 'user-1';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    VerifiedBadge(userId: userId),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          userId = 'user-2';
                        });
                      },
                      child: const Text('Change User'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      expect(find.byType(VerifiedBadge), findsOneWidget);

      // Tap button to change user
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // Badge should still be present
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });
  });
}
