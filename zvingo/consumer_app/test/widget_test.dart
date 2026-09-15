import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:consumer_app/main.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('zvingo_test_');
    Hive.init(hiveDirectory.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('App starts smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ZvingoConsumerApp()));
    // The sign-in form enters with the design system's staggered animation
    // (§4.3), so settle before asserting — otherwise the stagger's timers are
    // still pending when the tree is torn down.
    await tester.pumpAndSettle();
    // Verify the app renders
    expect(find.text('Good food is close'), findsOneWidget);
  });
}
