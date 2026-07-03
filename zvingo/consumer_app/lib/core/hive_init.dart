import 'package:consumer_app/features/address/saved_address.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveInit {
  static Future<void> init() async {
    await Hive.initFlutter();

    // Register Adapters
    Hive.registerAdapter(SavedAddressAdapter());

    // Open Boxes
    await Hive.openBox('cart');
    await Hive.openBox('settings');
    await Hive.openBox('cache');
    await Hive.openBox<SavedAddress>('addresses');
  }
}
