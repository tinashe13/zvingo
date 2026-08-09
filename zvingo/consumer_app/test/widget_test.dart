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
    // Verify the app renders
    expect(find.text('Good food is close'), findsOneWidget);
  });
}
