import 'package:flutter_test/flutter_test.dart';

import 'package:onenet_sol/main.dart';

void main() {
  testWidgets('launch gate renders security prompt', (tester) async {
    await tester.pumpWidget(const DatabaseUtilitiesApp());

    expect(find.text('Launch Security'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
