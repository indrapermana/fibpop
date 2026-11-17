import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/app/fibpop_app.dart';

void main() {
  testWidgets('shows the FIBPOP M0 landing screen', (tester) async {
    await tester.pumpWidget(const FibpopApp());

    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });

  testWidgets('navigates to the offline play placeholder and back', (
    tester,
  ) async {
    await tester.pumpWidget(const FibpopApp());

    await tester.tap(find.text('Offline play'));
    await tester.pumpAndSettle();
    expect(find.text('Offline play is not available yet.'), findsOneWidget);
    expect(find.text('FIBPOP\nM0 foundation'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });
}
