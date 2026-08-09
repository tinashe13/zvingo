# Building the Zvingo Consumer App

## API endpoint configuration

The API URL is supplied at build time with `--dart-define=API_BASE_URL=...` and
must include the `/api` prefix.

| Environment | Value |
| --- | --- |
| Android emulator | `http://10.0.2.2/api` (debug default) |
| Staging device | `http://<server-ip>/api` |
| Production | `https://api.zvingo.com/api` |

Debug development:

```sh
flutter run
flutter run --dart-define=API_BASE_URL=http://192.168.1.50/api
```

Release builds validate the endpoint at startup and reject non-HTTPS URLs:

```sh
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.zvingo.com/api
```

## Android release signing

Release tasks fail when signing is not configured. This prevents a debug-signed
artifact from being mistaken for a deployable build.

1. Create a keystore and keep it outside version control:

   ```sh
   keytool -genkey -v -keystore %USERPROFILE%\zvingo-consumer.jks -keyalg RSA -keysize 2048 -validity 10000 -alias consumer
   ```

2. Create `android/key.properties` (gitignored):

   ```properties
   storePassword=<store password>
   keyPassword=<key password>
   keyAlias=consumer
   storeFile=C:/Users/<you>/zvingo-consumer.jks
   ```

3. Run the app bundle command above. Gradle loads the keystore automatically.

For a local, explicitly non-deployable release-mode smoke build, set either the
Gradle project property `allowDebugReleaseSigning=true` or the environment
variable `ZVINGO_ALLOW_DEBUG_RELEASE_SIGNING=true`. Never upload that artifact
to a store.

## Preflight checklist

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.zvingo.com/api
```

Before upload, confirm the production API hostname, Android keystore, iOS signing
team, store listing, privacy policy, and final version/build number.
