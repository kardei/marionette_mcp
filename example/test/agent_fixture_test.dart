import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_example/main.dart';

void main() {
  testWidgets('fixture exposes stable key targets and long-press state', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.byKey(const ValueKey('nav_profile')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav_profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('name_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile_submit')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('long_press_target')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('long_press_target')), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('long_press_target')));
    await tester.pumpAndSettle();
    expect(find.text('Long press count: 1'), findsOneWidget);
  });
}
