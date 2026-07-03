import 'package:hive_flutter/hive_flutter.dart';

/// Initialize Hive for local persistence.
class HiveInit {
  static Future<void> init() async {
    await Hive.initFlutter();
    // Open default boxes
    await Hive.openBox('auth');
    await Hive.openBox('settings');
  }
}
