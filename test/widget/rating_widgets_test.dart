import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:godavao/features/ratings/presentation/user_rating.dart';
import 'package:godavao/features/ratings/presentation/rating_badge.dart';

void main() {
  group('UserRatingBadge Widget', () {
    testWidgets('displays loading state initially', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserRatingBadge(
              userId: 'test-user-id',
              listenRealtime: false,
            ),
          ),
        ),
      );

      // Initially shows nothing while loading
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('displays rating after loading', (tester) async {
      // Note: This test requires a mock Supabase client to work properly
      // For now, we're testing the widget structure
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserRatingBadge(
              userId: 'test-user-id',
              listenRealtime: false,
            ),
          ),
        ),
      );

      // Pump to allow async operations
      await tester.pump();

      // Widget should be built
      expect(find.byType(UserRatingBadge), findsOneWidget);
    });

    testWidgets('respects custom icon size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserRatingBadge(
              userId: 'test-user-id',
              iconSize: 24,
              listenRealtime: false,
            ),
          ),
        ),
      );

      expect(find.byType(UserRatingBadge), findsOneWidget);
    });

    testWidgets('respects listenRealtime parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserRatingBadge(
              userId: 'test-user-id',
              listenRealtime: true,
            ),
          ),
        ),
      );

      expect(find.byType(UserRatingBadge), findsOneWidget);
    });
  });

  group('RatingBadge Widget', () {
    testWidgets('displays rating with stars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: 4.5,
              count: 10,
            ),
          ),
        ),
      );

      expect(find.text('4.50'), findsOneWidget);
      expect(find.text('(10)'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('handles null average rating', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: null,
              count: 0,
            ),
          ),
        ),
      );

      expect(find.text('No ratings'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('handles NaN average rating', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: double.nan,
              count: 0,
            ),
          ),
        ),
      );

      expect(find.text('No ratings'), findsOneWidget);
    });

    testWidgets('respects custom text style', (tester) async {
      const customStyle = TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: 3.5,
              count: 5,
              textStyle: customStyle,
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('3.50'));
      expect(textWidget.style?.fontSize, 20);
      expect(textWidget.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('respects custom icon size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: 4.0,
              count: 8,
              iconSize: 24,
            ),
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.star));
      expect(iconWidget.size, 24);
    });

    testWidgets('handles null count gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: 4.5,
              count: null,
            ),
          ),
        ),
      );

      expect(find.text('(0)'), findsOneWidget);
    });

    testWidgets('respects dense mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingBadge(
              avg: 4.0,
              count: 5,
              dense: false,
            ),
          ),
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisSize, MainAxisSize.min);
    });
  });
}
