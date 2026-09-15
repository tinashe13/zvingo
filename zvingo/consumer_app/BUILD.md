# Building the Zvingo Consumer App

Everything you need to produce a release build of the customer-facing app, plus
the accounts and keys required to ship it. Provider signup instructions, costs
and lead times live in [`docs/INTEGRATIONS_AND_CREDENTIALS.md`](../docs/INTEGRATIONS_AND_CREDENTIALS.md).

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

The API URL is supplied **at build time** with `--dart-define=API_BASE_URL=...`
and **must include the `/api` suffix**. It is read once in
`lib/core/app_config.dart`.

> ⚠️ The driver app uses the **opposite** convention — its `API_BASE_URL` is the
> server root with **no** `/api` suffix. Passing a consumer-style value to the
> driver build (or vice versa) produces silently broken URLs.

| Environment | Value |
| --- | --- |
| Android emulator | `http://10.0.2.2/api` |
| iOS simulator | `http://127.0.0.1/api` |
| Staging device | `http://<server-ip>/api` |
| Production | `https://api.your-domain.com/api` |

Because the value is compiled into the binary, **changing the API host later
means a new build and a new store submission.** Settle the production domain
before you build. (The repo is currently inconsistent — nginx and the compose
examples use one name, the Dart default uses another. Reconcile them first.)

```sh
# debug, against a device on your LAN
flutter run --dart-define=API_BASE_URL=http://192.168.1.50/api
```

### Two guards will stop a bad endpoint

1. `AppConfig.validate()` throws at start-up in release builds if the scheme is
   not `https`.
2. `android/app/src/main/res/xml/network_security_config.xml` sets
   `cleartextTrafficPermitted="false"` for everything except `10.0.2.2`,
   `10.0.3.2`, `localhost` and `127.0.0.1`.

Together this means **a release build without TLS on the API host cannot work**.
Get the certificate before you build (integrations doc §2.8).

> Known issue: the *debug* default in `lib/core/app_config.dart` is a cleartext
> `http://` URL pointing at a public domain, which guard (2) blocks. Pass
> `--dart-define=API_BASE_URL=http://10.0.2.2/api` explicitly for emulator work
> until that default is fixed.

---

## 2. Android release signing

Release tasks **fail** when signing is not configured. That is deliberate — it
stops a debug-signed artifact being mistaken for a deployable build.

1. Create a keystore and keep it outside version control:

   ```sh
   keytool -genkey -v -keystore ~/keys/zvingo-consumer.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias consumer
   ```

   Windows: `keytool -genkey -v -keystore %USERPROFILE%\zvingo-consumer.jks ...`

2. Create `android/key.properties` (gitignored — keep it that way):

   ```properties
   storePassword=<store password>
   keyPassword=<key password>
   keyAlias=consumer
   storeFile=/home/you/keys/zvingo-consumer.jks
   ```

3. Build. Gradle loads the keystore automatically when the file exists.

**Back the `.jks` file up in two places** and store both passwords in the
company password manager. Also **opt in to Play App Signing** when you create
the Play listing: Google then holds the real app-signing key and your keystore
becomes only the *upload* key, which Google can reset if you lose it. Without
Play App Signing, a lost keystore means you can never update the app again.

For a local, explicitly **non-deployable** release-mode smoke build, set either
the Gradle property `-PallowDebugReleaseSigning=true` or the environment
variable `ZVINGO_ALLOW_DEBUG_RELEASE_SIGNING=true`. The artifact is debug-signed;
never upload it to a store.

---

## 3. iOS signing

Requires an **Apple Developer Program** membership (US$99/year; allow 1–3 weeks
for an organization enrolment — integrations doc §4.2).

- Bundle ID: **`com.zvingo.consumerApp`** — register it under
  Certificates, Identifiers & Profiles, exactly as spelled.
- Set `DEVELOPMENT_TEAM` in Xcode (`CODE_SIGN_STYLE` is already `Automatic`).
- `Info.plist` already carries `NSLocationWhenInUseUsageDescription`.
  Do **not** add background-location keys to this app — there is no
  justification for them and asking will get the listing rejected.
- **Outstanding:** this app has no `PrivacyInfo.xcprivacy`. App Store Connect
  rejects submissions that use a required-reason API without one, and several
  plugins here (`geolocator`, `connectivity_plus`, `hive`) do. Create it before
  the first iOS submission.

---

## 4. Release builds

```sh
# Android App Bundle for Play
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com/api

# APK for direct distribution / testing
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com/api

# iOS
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com/api
```

---

## 5. Preflight checklist

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.your-domain.com/api
```

Before upload, confirm:

- [ ] The production API hostname is correct and matches nginx `server_name`
- [ ] The API host has a valid TLS certificate (release builds refuse plain HTTP)
- [ ] `android/key.properties` present, keystore backed up in two places
- [ ] Play App Signing opted in
- [ ] iOS `DEVELOPMENT_TEAM` set and `PrivacyInfo.xcprivacy` created
- [ ] **Privacy policy URL** live and reachable (mandatory for both stores)
- [ ] **Account deletion** path available in-app and on the web (Play requires it)
- [ ] Play **Data safety** form completed — precise location, phone number, name,
      address, purchase history, photos. See integrations doc §4.3.
- [ ] App Store **App Privacy** questionnaire completed to match
- [ ] Store listing assets ready (icon, feature graphic, screenshots, descriptions)
- [ ] Version and build number bumped in `pubspec.yaml`
