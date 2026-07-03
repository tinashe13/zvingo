# Building the Zvingo Driver App

## API endpoint configuration

The server base URL is centralized in `lib/core/app_config.dart` and set at
build time via `--dart-define=API_BASE_URL=...`. **Note:** the value is the
server root (no `/api` suffix); the WebSocket URL (`ws://` / `wss://`) is
derived from it automatically.

| Environment              | Value                                |
| ------------------------ | ------------------------------------ |
| Android emulator (dev)   | `http://10.0.2.2:8000` *(default)*   |
| iOS simulator (dev)      | `http://127.0.0.1:8000`              |
| Real device / staging    | `http://<server-ip>`                 |
| Production               | `https://api.zvingo.com`             |

No flag is needed for everyday development — the default targets the Android
emulator's host loopback.

## Debug / dev

```sh
flutter run
# or against a staging server:
flutter run --dart-define=API_BASE_URL=http://192.168.1.50
```

## Release build

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://api.zvingo.com
# or an app bundle for Play Store:
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.zvingo.com
```

Release builds must use `https://` — cleartext HTTP is blocked except for local
dev hosts (see `android/app/src/main/res/xml/network_security_config.xml`).

## Release signing setup (one-time)

Without this, release builds fall back to **debug signing** (fine for local
testing, not distributable).

1. Create a keystore (keep it out of version control — it is gitignored):

   ```sh
   keytool -genkey -v -keystore %USERPROFILE%\zvingo-driver.jks -keyalg RSA -keysize 2048 -validity 10000 -alias driver
   ```

2. Create `android/key.properties` (also gitignored):

   ```properties
   storePassword=<store password>
   keyPassword=<key password>
   keyAlias=driver
   storeFile=C:/Users/<you>/zvingo-driver.jks
   ```

3. Build as above — `android/app/build.gradle` picks up `key.properties`
   automatically when present.
