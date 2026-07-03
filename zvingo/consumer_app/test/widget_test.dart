import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:consumer_app/main.dart';

void main() {
  testWidgets('App starts smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ZvingoConsumerApp()));
    // Verify the app renders
    expect(find.text('Login'), findsOneWidget);
  });
}
