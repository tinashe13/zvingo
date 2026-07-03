import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:driver_app/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ZvingoDriverApp()),
    );
    await tester.pumpAndSettle();
    // App should render without errors
    expect(find.byType(ZvingoDriverApp), findsOneWidget);
  });
}
