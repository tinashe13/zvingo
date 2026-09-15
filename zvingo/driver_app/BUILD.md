# Building the Zvingo Driver App

Everything you need to produce a release build of the courier app, plus the
accounts and keys required to ship it. Provider signup instructions, costs and
lead times live in [`docs/INTEGRATIONS_AND_CREDENTIALS.md`](../docs/INTEGRATIONS_AND_CREDENTIALS.md).

## Prerequisites

```sh
export PATH="/opt/flutter/bin:$PATH"
flutter pub get
```

After editing any file with Riverpod or Hive annotations:

```sh
dart run build_runner build --delete-conflicting-outputs
```

---

## 1. API endpoint configuration

The server base URL is centralised in `lib/core/app_config.dart` and set at
build time with `--dart-define=API_BASE_URL=...`.

> ⚠️ **The value is the server ROOT, with NO `/api` suffix** — the opposite of
> the consumer app's convention. The WebSocket URL (`ws://` / `wss://`) is
> derived from it automatically by swapping the scheme. Passing a consumer-style
> `.../api` value here produces silently broken URLs.

| Environment | Value |
| --- | --- |
| Android emulator (dev) | `http://10.0.2.2:8000` *(default)* |
| iOS simulator (dev) | `http://127.0.0.1:8000` |
| Real device / staging | `http://<server-ip>` |
| Production | `https://api.your-domain.com` |

No flag is needed for everyday development — the default targets the Android
emulator's host loopback.

Because the value is compiled into the binary, **changing the API host later
means a new build and a new store submission.** Settle the production domain
before you build.

```sh
flutter run
# or against a staging server on your LAN:
flutter run --dart-define=API_BASE_URL=http://192.168.1.50
```

Release builds must use `https://` — cleartext HTTP is blocked except for local
dev hosts (`android/app/src/main/res/xml/network_security_config.xml`). Get the
TLS certificate before you build (integrations doc §2.8).

**BinProto note:** the driver app also talks to the backend directly on UDP 9090
and TCP 9091 for location telemetry. Those bypass nginx and TLS by design, so
the host firewall must allow them — and be aware the traffic is currently
plaintext.

---

## 2. Android release signing

1. Create a keystore and keep it outside version control:

   ```sh
   keytool -genkey -v -keystore ~/keys/zvingo-driver.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias driver
   ```

   Windows: `keytool -genkey -v -keystore %USERPROFILE%\zvingo-driver.jks ...`

2. Create `android/key.properties` (gitignored — keep it that way):

   ```properties
   storePassword=<store password>
   keyPassword=<key password>
   keyAlias=driver
   storeFile=/home/you/keys/zvingo-driver.jks
   ```

3. Build as below — `android/app/build.gradle` picks up `key.properties`
   automatically when present.

> 🔴 **Read this before your first upload.** Unlike the consumer app, this
> project **silently falls back to debug signing** when `key.properties` is
> missing, instead of failing the build. So
> `flutter build appbundle --release` on a fresh machine produces an AAB that
> looks fine and is rejected by Play at upload. **Always confirm
> `android/key.properties` exists before building for release**, and verify the
> signer afterwards:
>
> ```sh
> jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab | head -20
> # "CN=Android Debug" means you built the wrong thing.
> ```
>
> (Mirroring the consumer app's `gradle.taskGraph.whenReady` guard is tracked in
> the integrations doc §8.)

**Back the `.jks` file up in two places** and store both passwords in the
company password manager. **Opt in to Play App Signing** when creating the Play
listing — Google then holds the real signing key and your keystore is only the
upload key, which Google can reset if you lose it.

---

## 3. iOS signing

Requires an **Apple Developer Program** membership (US$99/year; allow 1–3 weeks
for an organization enrolment — integrations doc §4.2).

- Bundle ID: **`com.zvingo.driverApp`** — register it under
  Certificates, Identifiers & Profiles, exactly as spelled.
- Set `DEVELOPMENT_TEAM` in Xcode (`CODE_SIGN_STYLE` is already `Automatic`).

> 🔴 **Blocker: `ios/Runner/Info.plist` has no location usage string.**
> This app depends on `geolocator`, and **iOS terminates the process** the
> instant it requests location without `NSLocationWhenInUseUsageDescription`.
> The iOS build is not shippable until it is added. Something like:
>
> ```xml
> <key>NSLocationWhenInUseUsageDescription</key>
> <string>Zvingo Driver uses your location to match you with nearby orders and to show the customer where their delivery is.</string>
> ```
>
> Vague strings get rejected; name the user benefit.

> **Outstanding:** no `PrivacyInfo.xcprivacy`. App Store Connect rejects
> submissions that use a required-reason API without one, and `geolocator`,
> `connectivity_plus` and `hive` all do. Create it before the first submission.

Also note `CFBundleDisplayName` is currently `Driver App` and `CFBundleName` is
`driver_app`; the Android `android:label` is likewise `driver_app`. Set a real
product name before you ship.

---

## 4. Background location — decide before you submit

The app currently requests **no background location**: there is no
`ACCESS_BACKGROUND_LOCATION` permission, no foreground service, and no
`UIBackgroundModes: location`.

**Consequence:** driver tracking stops when the phone locks or the driver
switches apps — most of a delivery. Customers watch the driver freeze.

If you add it, both stores require extra work with a long review tail, and it is
much cheaper to do at first submission than as an update:

- **Android:** declare the permission *and* run a foreground service with
  `foregroundServiceType="location"` and a persistent notification, then complete
  the Play permissions-declaration form including a **video of 30 seconds or
  less** showing how to log in and invoke the feature. Frame the justification
  around the **customer** being able to watch their delivery, and request the
  permission **only while a delivery is active**.
- **iOS:** add `NSLocationAlwaysAndWhenInUseUsageDescription` and
  `UIBackgroundModes: ["location"]`, with a purpose string that matches what the
  app actually does.

Full guidance and the exact reviewer justifications: integrations doc §4.4.

---

## 5. Release builds

```sh
# Android App Bundle for Play
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com

# APK for direct distribution / testing
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com

# iOS
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com
```

---

## 6. Preflight checklist

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.your-domain.com
```

Before upload, confirm:

- [ ] `android/key.properties` **exists** and the AAB is not debug-signed
      (`jarsigner -verify -certs ...`)
- [ ] Production API hostname correct, **no** `/api` suffix, HTTPS
- [ ] Host firewall allows UDP 9090 and TCP 9091 for BinProto telemetry
- [ ] Play App Signing opted in; keystore backed up in two places
- [ ] iOS `NSLocationWhenInUseUsageDescription` added (otherwise the app crashes)
- [ ] iOS `DEVELOPMENT_TEAM` set and `PrivacyInfo.xcprivacy` created
- [ ] App display name is a real product name, not `driver_app`
- [ ] **Privacy policy URL** live and reachable (mandatory for both stores)
- [ ] **Account deletion** path available in-app and on the web (Play requires it)
- [ ] Play **Data safety** form completed — and it must declare that the
      driver's precise location is **shared with another user** (the customer).
      See integrations doc §4.3.
- [ ] Background-location decision made, and if yes the declaration form and
      30-second demo video are ready
- [ ] Store listing assets ready (icon, feature graphic, screenshots, descriptions)
- [ ] Version and build number bumped in `pubspec.yaml`
