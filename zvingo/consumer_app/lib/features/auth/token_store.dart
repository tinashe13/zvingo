import 'package:hive/hive.dart';

import 'package:consumer_app/features/address/saved_address.dart';

/// Where the session lives on device.
///
/// `access_token` keeps the key `core/api_client.dart` already reads, so the
/// request interceptor there keeps working untouched. Everything else this
/// store owns is new: the rotating refresh token, the access token's expiry,
/// and the cached user id.
///
/// **Nothing here is ever logged or rendered.** `toString()` is deliberately
/// not overridden to include values, and the password-reset code is not stored
/// at all — it lives only in the text field the user typed it into.
class TokenStore {
  const TokenStore._();

  static const String boxName = 'settings';

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _expiresAtKey = 'access_token_expires_at';
  static const String _userIdKey = 'user_id';

  /// Untyped boxes that hold something about *this* signed-in person. Sign-out
  /// empties every one of them — a shared phone must not leak the previous
  /// user's cart, favourites or search history to the next one. The typed
  /// `addresses` box is cleared separately in [clearEverything].
  static const List<String> signedInBoxes = <String>[
    'cart',
    'cache',
    'favourites',
    'search_history',
  ];

  static Box get _box => Hive.box(boxName);

  static String? get accessToken {
    final value = _box.get(_accessKey);
    final token = value?.toString();
    return (token == null || token.isEmpty) ? null : token;
  }

  static String? get refreshToken {
    final value = _box.get(_refreshKey);
    final token = value?.toString();
    return (token == null || token.isEmpty) ? null : token;
  }

  static String? get userId {
    final value = _box.get(_userIdKey);
    final id = value?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// When the current access token stops being accepted, if the server told us.
  static DateTime? get expiresAt {
    final millis = _box.get(_expiresAtKey);
    if (millis is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  static bool get isSignedIn => accessToken != null;

  /// True when the access token is within [leeway] of expiry (or already gone).
  ///
  /// The client refreshes *before* the request rather than after a 401, so a
  /// user mid-checkout never sees a failed call at all.
  static bool expiresWithin(Duration leeway) {
    final at = expiresAt;
    if (at == null) return false;
    return DateTime.now().toUtc().add(leeway).isAfter(at);
  }

  /// Persist a `Token` response from `/auth/token`, `/auth/register`,
  /// `/auth/otp/verify` or `/auth/refresh`.
  ///
  /// `refresh_token` and `expires_in` are optional in the schema, so a server
  /// that omits them leaves the previous values in place rather than wiping a
  /// working session.
  static Future<void> saveTokenResponse(Map<String, dynamic> data) async {
    final access = data['access_token']?.toString();
    if (access == null || access.isEmpty) return;

    final refresh = data['refresh_token']?.toString();
    final expiresIn = data['expires_in'];

    await _box.put(_accessKey, access);
    if (refresh != null && refresh.isNotEmpty) {
      await _box.put(_refreshKey, refresh);
    }
    if (expiresIn is num && expiresIn > 0) {
      await _box.put(
        _expiresAtKey,
        DateTime.now()
            .toUtc()
            .add(Duration(seconds: expiresIn.toInt()))
            .millisecondsSinceEpoch,
      );
    } else {
      // No expiry advertised — don't keep a stale one that would trigger
      // pointless refreshes.
      await _box.delete(_expiresAtKey);
    }
  }

  static Future<void> saveUserId(String? id) async {
    if (id == null || id.isEmpty) return;
    await _box.put(_userIdKey, id);
  }

  /// Drop the session only. Used when a refresh fails: the person is signed
  /// out, but their saved addresses and cart survive for when they sign back in.
  static Future<void> clearSession() async {
    await _box.delete(_accessKey);
    await _box.delete(_refreshKey);
    await _box.delete(_expiresAtKey);
    await _box.delete(_userIdKey);
  }

  /// Full sign-out: session plus every box that holds this person's data.
  static Future<void> clearEverything() async {
    await clearSession();
    for (final name in signedInBoxes) {
      try {
        final box =
            Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
        await box.clear();
      } catch (_) {
        // A box that was never created on this device has nothing to clear.
      }
    }
    try {
      final addresses = Hive.isBoxOpen('addresses')
          ? Hive.box<SavedAddress>('addresses')
          : await Hive.openBox<SavedAddress>('addresses');
      await addresses.clear();
    } catch (_) {
      // Same: absent box, nothing to clear.
    }
  }
}
