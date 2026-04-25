# Scent & Sense — Flutter App (v5.2.5)

Internal-company app for the Scent & Sense laboratory diffuser
product. Distributed as an internal APK — **not** on Google Play.

## Stack

- Flutter 3.x / Dart 3.x
- `flutter_riverpod` state management
- `dio` HTTP client + `socket_io_client` for realtime updates
- `flutter_reactive_ble` for BLE onboarding
  - pinned via `third_party/reactive_ble_mobile` (path override) to
    fix the upstream Java-1.8 / Kotlin-17 JVM-target mismatch; see
    `CHANGELOG_v5_2_4.md` and `CHANGELOG_v5_2_5.md`
- `flutter_secure_storage` for the JWT token
- `permission_handler` for BLE / location permissions

## Build

```bash
# dev run on a real device on the same Wi-Fi as the dev backend
flutter run \
  --dart-define=APP_ENV=dev \
  --dart-define=API_BASE_URL=http://<your-lan-ip>:3000

# production release APK — talks to the public Render backend
flutter build apk --release \
  --dart-define=APP_ENV=prod
#   (equivalent to API_BASE_URL=https://diffuser-backend-1.onrender.com
#    which is the compile-time default in app/lib/core/config/app_config.dart)

# override the prod backend URL per-build (e.g. staging / custom domain)
flutter build apk --release \
  --dart-define=APP_ENV=prod \
  --dart-define=API_BASE_URL=https://api.scentandsense.example