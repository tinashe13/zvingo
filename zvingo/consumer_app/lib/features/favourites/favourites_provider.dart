import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favourites_provider.g.dart';

/// Manages favourite restaurant IDs — persisted in Hive
@Riverpod(keepAlive: true)
class Favourites extends _$Favourites {
  static const _boxName = 'favourites';
  static const _key = 'restaurant_ids';

  @override
  Set<String> build() {
    _loadFromHive();
    return {};
  }

  Future<void> _loadFromHive() async {
    final box = await Hive.openBox(_boxName);
    final stored = box.get(_key, defaultValue: <dynamic>[]);
    state = Set<String>.from(stored);
  }

  Future<void> toggle(String restaurantId) async {
    final updated = Set<String>.from(state);
    if (updated.contains(restaurantId)) {
      updated.remove(restaurantId);
    } else {
      updated.add(restaurantId);
    }
    state = updated;
    final box = await Hive.openBox(_boxName);
    await box.put(_key, updated.toList());
  }

  bool isFavourite(String restaurantId) => state.contains(restaurantId);
}
