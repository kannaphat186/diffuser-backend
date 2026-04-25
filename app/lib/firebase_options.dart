// lib/firebase_options.dart — v6.0.0
// ─────────────────────────────────────────────────────────────
// Values below are taken from the Firebase Android app registered
// under the `diffuser-ea88` project with package name `com.diffuser.app`.
//
// The Android applicationId in android/app/build.gradle.kts is now
// also `com.diffuser.app`, so FCM delivery works out of the box.
//
// If you later re-brand to a different package name, add that package
// in the Firebase Console and regenerate this file:
//   flutterfire configure --project=diffuser-ea88
// ─────────────────────────────────────────────────────────────
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web is not a target for the Scent & Sense app. '
        'Regenerate via `flutterfire configure` if you add web support.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS is not wired yet. Add an iOS app to the `diffuser-ea88` Firebase '
          'project and regenerate this file with `flutterfire configure`.',
        );
      default:
        throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
    }
  }

  // Values from google-services.json (com.diffuser.app).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDH9Tir8rHW7jkH-gCugdzdazpiGBlbET0',
    appId: '1:698419620271:android:331d08b9de97c376a9675a',
    messagingSenderId: '698419620271',
    projectId: 'diffuser-ea88',
    storageBucket: 'diffuser-ea88.firebasestorage.app',
  );
}
