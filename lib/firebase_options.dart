import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Generated for DrivingBuddy (Web & Android).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAum8uMB6-dkjhQURAlKB-d0sGPx7n7uwg',
    appId: '1:587027656702:web:2aa27ac2baa208eb401aaf',
    messagingSenderId: '587027656702',
    projectId: 'drivinbuddy',
    authDomain: 'drivinbuddy.firebaseapp.com',
    databaseURL: 'https://drivinbuddy-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'drivinbuddy.firebasestorage.app',
    measurementId: 'G-VCXK8V21YR',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyASbcMqXcvuY7KgQsd-YVbUwWHc2zXRgQ0',
    appId: '1:587027656702:android:65a6dbfcbc1ec09e401aaf',
    messagingSenderId: '587027656702',
    projectId: 'drivinbuddy',
    databaseURL: 'https://drivinbuddy-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'drivinbuddy.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAum8uMB6-dkjhQURAlKB-d0sGPx7n7uwg',
    appId: '1:587027656702:ios:placeholder',
    messagingSenderId: '587027656702',
    projectId: 'drivinbuddy',
    databaseURL: 'https://drivinbuddy-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'drivinbuddy.firebasestorage.app',
  );
}
