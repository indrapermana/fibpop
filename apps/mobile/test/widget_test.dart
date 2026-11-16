import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/main.dart';

void main() {
  testWidgets('shows the FIBPOP M0 landing screen', (tester) async {
    await tester.pumpWidget(const FibpopApp());

    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });
}
