# Building the Zvingo Consumer App

## API endpoint configuration

The API base URL is centralized in `lib/core/app_config.dart` and set at build
time via `--dart-define=API_BASE_URL=...`. **Note:** the value includes the
`/api` path prefix (the backend is served behind Nginx under `/api`).

| Environment              | Value                              |
| ------------------------ | ---------------------------------- |
| Android emulator (dev)   | `http://10.0.2.2/api` *(default)*  |
| Real device / staging    | `http://<server-ip>/api`           |
| Production               | `https://api.zvingo.com/api`       |

No flag is needed for everyday development — the default targets the Android
emulator's host loopback.

## Debug / dev

```sh
flutter run
# or against a staging server:
flutter run --dart-define=API_BASE_URL=http://192.168.1.50/api
```

## Release build

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://api.zvingo.com/api
# or an app bundle for Play Store:
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.zvingo.com/api
```

Release builds must use `https://` — cleartext HTTP is blocked except for local
dev hosts (see `android/app/src/main/res/xml/network_security_config.xml`).

## Release signing setup (one-time)

Without this, release builds fall back to **debug signing** (fine for local
testing, not distributable).

1. Create a keystore (keep it out of version control — it is gitignored):

   ```sh
   keytool -genkey -v -keystore %USERPROFILE%\zvingo-consumer.jks -keyalg RSA -keysize 2048 -validity 10000 -alias consumer
   ```

2. Create `android/key.properties` (also gitignored):

   ```properties
   storePassword=<store password>
   keyPassword=<key password>
   keyAlias=consumer
   storeFile=C:/Users/<you>/zvingo-consumer.jks
   ```

3. Build as above — `android/app/build.gradle` picks up `key.properties`
   automatically when present.
