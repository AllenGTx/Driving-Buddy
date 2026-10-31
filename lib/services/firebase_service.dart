import '../models/account_config.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

// ============================================================================
// FIREBASE SERVICE — Authentication, Firestore Database, & Storage
// ============================================================================

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore firestore = FirebaseFirestore.instance;
final FirebaseStorage storage = FirebaseStorage.instance;

// ----------------------------------------------------------------------------
// AUTH SERVICE
// ----------------------------------------------------------------------------
class AuthService {
  /// Cek status login
  static bool get isLoggedIn => auth.currentUser != null;

  /// Ambil User aktif
  static User? get currentUser => auth.currentUser;

  /// Ambil nama user langsung dari metadata / Firestore
  static String? get currentUserName => currentUser?.displayName;

  /// Stream perubahan status auth
  static Stream<User?> get authStateChanges => auth.authStateChanges();

  /// Registrasi akun baru (Email & Password)
  static Future<UserCredential> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(fullName);
      try {
        await user.sendEmailVerification();
      } catch (e) {
        debugPrint('Kirim verifikasi email error: ');
      }
      // Simpan profile dokumen ke Firestore
      await firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': email.trim(),
        'displayName': fullName,
        'photoUrl': null,
        'createdAt': FieldValue.serverTimestamp(),
        'totalTrips': 0,
        'overallAvgScore': 100,
      }, SetOptions(merge: true));
    }

    return credential;
  }

  /// Login email & password
  static Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Sinkronisasi data user di firestore jika belum ada
    final user = credential.user;
    if (user != null) {
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        await firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName ?? 'Pengemudi',
          'photoUrl': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    return credential;
  }

  static String? lastAttemptedGoogleEmail;

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '587027656702-kgmmt061b1js71rd9ss6tti2so2sv4bv.apps.googleusercontent.com',
  );

  /// Login langsung via Akun Google (One-Tap Native Android/iOS Account Chooser)
  static Future<UserCredential> signInWithGoogle() async {
    UserCredential credential;
    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');
      credential = await auth.signInWithPopup(googleProvider);
    } else {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      GoogleSignInAccount? googleUser;
      GoogleSignInAuthentication? googleAuth;

      try {
        googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw FirebaseAuthException(
            code: 'popup-closed-by-user',
            message: 'Login Google dibatalkan.',
          );
        }

        lastAttemptedGoogleEmail = googleUser.email;
        googleAuth = await googleUser.authentication;
      } catch (nativeErr) {
        debugPrint('Native GoogleSignIn / auth error: $nativeErr');
        final errStr = nativeErr.toString().toLowerCase();

        if (nativeErr is FirebaseAuthException && nativeErr.code == 'popup-closed-by-user') {
          rethrow;
        }
        if (errStr.contains('popup-closed-by-user') ||
            errStr.contains('closed by user') ||
            errStr.contains('cancel') ||
            errStr.contains('12501')) {
          throw FirebaseAuthException(
            code: 'popup-closed-by-user',
            message: 'Login Google dibatalkan.',
          );
        }

        // Jika terjadi error sertifikat hash paket pada microG / Play Services,
        // langsung fallback otomatis ke Browser OAuth Provider
        debugPrint('Falling back seamlessly to auth.signInWithProvider...');
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        return await auth.signInWithProvider(googleProvider);
      }

      if (googleAuth.idToken == null) {
        debugPrint('Google idToken is null, trying fallback to browser OAuth...');
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        return await auth.signInWithProvider(googleProvider);
      }

      final OAuthCredential oAuthCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      credential = await auth.signInWithCredential(oAuthCredential);
    }

    final user = credential.user;
    if (user != null) {
      // JANGAN TIMPA FOTO PROFIL: Cek apakah user sudah punya foto profil sebelumnya
      bool hasExistingPhoto = false;
      String? savedCustomPhoto;
      try {
        final existingDoc = await firestore.collection('users').doc(user.uid).get();
        final existingPhoto = existingDoc.data()?['photoUrl'] as String?;
        if (existingPhoto != null && existingPhoto.trim().isNotEmpty) {
          hasExistingPhoto = true;
          savedCustomPhoto = existingPhoto.trim();
        }
      } catch (_) {}

      await firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? 'Pengemudi',
        if (!hasExistingPhoto && user.photoURL != null && user.photoURL!.isNotEmpty)
          'photoUrl': user.photoURL,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // SINKRONKAN LANGSUNG KE AccountConfig SEGERA (Cegah munculnya foto Tanjiro)
      final photoToSet = hasExistingPhoto ? savedCustomPhoto : user.photoURL;
      if (photoToSet != null && photoToSet.isNotEmpty) {
        await AccountConfig.setPhotoUrl(photoToSet, userEmail: user.email);
      }
    }

    return credential;
  }

  /// Reset Password via link Email
  static Future<void> resetPassword(String email) async {
    await auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Logout
  static Future<void> logout() async {
    await auth.signOut();
  }

  /// Ambil nama lengkap pengemudi
  static Future<String> getUserName() async {
    final user = currentUser;
    if (user == null) return 'Pengemudi';

    try {
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final name = doc.data()!['displayName'] as String?;
        if (name != null && name.trim().isNotEmpty) return name;
      }
    } catch (e) {
      debugPrint('Firestore getUserName error: $e');
    }

    return user.displayName ?? user.email?.split('@').first ?? 'Pengemudi';
  }

  /// Ambil data profil lengkap (nama, email, photoUrl)
  static Future<Map<String, dynamic>?> getUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (doc.exists) return doc.data();
    } catch (e) {
      debugPrint('Firestore getUserProfile error: $e');
    }

    return {
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName ?? 'Pengemudi',
      'photoUrl': user.photoURL,
    };
  }

  /// Update nama pengemudi
  static Future<void> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) return;

    await user.updateDisplayName(name);
    await firestore.collection('users').doc(user.uid).set({
      'displayName': name,
    }, SetOptions(merge: true));
  }

  /// Upload dan perbarui foto profil (dari file kamera / galeri) ke Firebase Storage & Firestore
  static Future<String?> uploadProfileImage(File file) async {
    final user = currentUser;
    if (user == null) {
      // Jika mode tamu offline, kembalikan path lokal file agar tetap bisa tampil
      return file.path;
    }

    try {
      final ref = storage.ref().child('user_avatars/${user.uid}.jpg');
      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      await user.updatePhotoURL(downloadUrl);
      await firestore.collection('users').doc(user.uid).set({
        'photoUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage upload error: $e. Fallback ke path lokal.');
      return file.path;
    }
  }
}

// ----------------------------------------------------------------------------
// SESSION SERVICE — Riwayat Perjalanan & Telemetri Real-time
// ----------------------------------------------------------------------------
class SessionService {
  /// Mulai sesi baru di Firestore
  static Future<String?> startSession() async {
    final user = AuthService.currentUser;
    if (user == null) return null;

    final docRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .doc();

    await docRef.set({
      'id': docRef.id,
      'userId': user.uid,
      'startedAt': FieldValue.serverTimestamp(),
      'startedAtIso': DateTime.now().toIso8601String(),
      'status': 'in_progress',
    });

    return docRef.id;
  }

  /// Simpan hasil akhir sesi perjalanan
  static Future<void> endSession({
    required String sessionId,
    required int durationSeconds,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
    required double distanceKm,
    required int drivingScore,
    required double avgBlinkRate,
    required int totalYawns,
    required int totalDrowsyEvents,
    required int totalMicrosleeps,
    double? avgEar,
    double? avgMar,
    double? avgHeadTilt,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    List<Map<String, double>>? routePoints,
  }) async {
    final sessionPayload = {
      'id': sessionId,
      'durationSeconds': durationSeconds,
      'duration_seconds': durationSeconds,
      'avgSpeedKmh': avgSpeedKmh,
      'avg_speed_kmh': avgSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'max_speed_kmh': maxSpeedKmh,
      'distanceKm': distanceKm,
      'distance_km': distanceKm,
      'drivingScore': drivingScore,
      'driving_score': drivingScore,
      'avgBlinkRate': avgBlinkRate,
      'avg_blink_rate': avgBlinkRate,
      'totalYawns': totalYawns,
      'total_yawns': totalYawns,
      'totalDrowsyEvents': totalDrowsyEvents,
      'total_drowsy_events': totalDrowsyEvents,
      'totalMicrosleeps': totalMicrosleeps,
      'total_microsleeps': totalMicrosleeps,
      'avgEar': avgEar ?? 0.0,
      'avg_ear': avgEar ?? 0.0,
      'avgMar': avgMar ?? 0.0,
      'avg_mar': avgMar ?? 0.0,
      'avgHeadTilt': avgHeadTilt ?? 0.0,
      'avg_kemiringan_kepala': avgHeadTilt ?? 0.0,
      'avg_head_tilt': avgHeadTilt ?? 0.0,
      'startLat': startLat,
      'startLng': startLng,
      'start_lat': startLat,
      'start_lng': startLng,
      'endLat': endLat,
      'endLng': endLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'lastLat': endLat,
      'lastLng': endLng,
      'last_lat': endLat,
      'last_lng': endLng,
      if (routePoints != null && routePoints.isNotEmpty)
        'routePoints': routePoints,
      'status': 'completed',
      'endedAtIso': DateTime.now().toIso8601String(),
    };

    final user = AuthService.currentUser;
    if (user == null) {
      // User offline / guest: simpan ke cache lokal
      await saveSessionLocally(sessionPayload);
      return;
    }

    try {
      final docRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .doc(sessionId);

    await docRef.set({
      'endedAt': FieldValue.serverTimestamp(),
      'endedAtIso': DateTime.now().toIso8601String(),
      'durationSeconds': durationSeconds,
      'duration_seconds': durationSeconds, // kompatibilitas
      'avgSpeedKmh': avgSpeedKmh,
      'avg_speed_kmh': avgSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'max_speed_kmh': maxSpeedKmh,
      'distanceKm': distanceKm,
      'distance_km': distanceKm,
      'drivingScore': drivingScore,
      'driving_score': drivingScore,
      'avgBlinkRate': avgBlinkRate,
      'avg_blink_rate': avgBlinkRate,
      'totalYawns': totalYawns,
      'total_yawns': totalYawns,
      'totalDrowsyEvents': totalDrowsyEvents,
      'total_drowsy_events': totalDrowsyEvents,
      'totalMicrosleeps': totalMicrosleeps,
      'total_microsleeps': totalMicrosleeps,
      'avgEar': avgEar ?? 0.0,
      'avg_ear': avgEar ?? 0.0,
      'avgMar': avgMar ?? 0.0,
      'avg_mar': avgMar ?? 0.0,
      'avgHeadTilt': avgHeadTilt ?? 0.0,
      'avg_kemiringan_kepala': avgHeadTilt ?? 0.0,
      'avg_head_tilt': avgHeadTilt ?? 0.0,
      'startLat': startLat,
      'startLng': startLng,
      'start_lat': startLat,
      'start_lng': startLng,
      'endLat': endLat,
      'endLng': endLng,
      'end_lat': endLat,
      'end_lng': endLng,
      'lastLat': endLat,
      'lastLng': endLng,
      'last_lat': endLat,
      'last_lng': endLng,
      if (routePoints != null && routePoints.isNotEmpty)
        'routePoints': routePoints,
      'status': 'completed',
    }, SetOptions(merge: true));

    // Update agregat user
    try {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.update({
        'totalTrips': FieldValue.increment(1),
      });
    } catch (_) {}
    } catch (e) {
      debugPrint('Firestore offline fallback: ');
      // Jika upload gagal karena tidak ada koneksi / offline, simpan ke antrean lokal
      await saveSessionLocally(sessionPayload);
    }
  }

  /// Catat satu titik GPS
  static Future<void> addGpsPoint({
    required String sessionId,
    required double latitude,
    required double longitude,
    required double speedKmh,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('gps_tracks')
        .add({
      'latitude': latitude,
      'longitude': longitude,
      'speedKmh': speedKmh,
      'recordedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Log event kantuk / yawn / microsleep
  static Future<void> logEvent({
    required String sessionId,
    required String eventType, // 'drowsy' | 'yawn' | 'microsleep'
    double? ear,
    double? mar,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('detection_events')
        .add({
      'eventType': eventType,
      'event_type': eventType,
      'ear': ear,
      'mar': mar,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Ambil semua sesi perjalanan milik user (History)
  static Future<List<Map<String, dynamic>>> getUserSessions() async {
    final user = AuthService.currentUser;
    final offlinePending = await getPendingOfflineSessions();

    if (user == null) {
      return offlinePending;
    }

    // Auto-sync jika ada koneksi
    if (offlinePending.isNotEmpty && await hasInternetConnection()) {
      syncPendingOfflineSessions();
    }

    try {
      final querySnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .orderBy('startedAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        // Normalisasi format tanggal untuk UI
        if (data['startedAt'] is Timestamp) {
          data['started_at'] =
              (data['startedAt'] as Timestamp).toDate().toIso8601String();
        } else if (data['startedAtIso'] != null) {
          data['started_at'] = data['startedAtIso'];
        }
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Firestore getUserSessions error: $e');
      return [];
    }
  }

  /// Stream riwayat sesi perjalanan real-time
  static Stream<List<Map<String, dynamic>>> getUserSessionsStream() {
    final user = AuthService.currentUser;
    if (user == null) return Stream.value([]);

    return firestore
        .collection('users')
        .doc(user.uid)
        .collection('sessions')
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              if (data['startedAt'] is Timestamp) {
                data['started_at'] =
                    (data['startedAt'] as Timestamp).toDate().toIso8601String();
              } else if (data['startedAtIso'] != null) {
                data['started_at'] = data['startedAtIso'];
              }
              return data;
            }).toList());
  }

  // ==========================================================================
  // OFFLINE SESSIONS CACHE & BACKGROUND SYNC (Local-First Architecture)
  // ==========================================================================
  static const _keyPendingSessions = 'offline_pending_sessions_queue';

  /// Simpan sesi ke cache lokal saat offline atau gagal terhubung ke cloud
  static Future<void> saveSessionLocally(Map<String, dynamic> sessionData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_keyPendingSessions);
      List<dynamic> list = [];
      if (existingJson != null && existingJson.isNotEmpty) {
        try {
          list = jsonDecode(existingJson) as List<dynamic>;
        } catch (_) {}
      }
      list.add(sessionData);
      await prefs.setString(_keyPendingSessions, jsonEncode(list));
      debugPrint('📦 Sesi disimpan ke offline cache lokal (Total pending: \)');
    } catch (e) {
      debugPrint('Gagal simpan sesi lokal: ');
    }
  }

  /// Ambil semua sesi lokal yang belum tersinkron
  static Future<List<Map<String, dynamic>>> getPendingOfflineSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_keyPendingSessions);
      if (existingJson == null || existingJson.isEmpty) return [];
      final decoded = jsonDecode(existingJson) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Sinkronisasikan seluruh antrean sesi offline ke Firestore saat ada koneksi internet
  static Future<int> syncPendingOfflineSessions() async {
    final user = AuthService.currentUser;
    if (user == null) return 0;

    final pending = await getPendingOfflineSessions();
    if (pending.isEmpty) return 0;

    int syncedCount = 0;
    List<Map<String, dynamic>> remaining = [];

    for (final s in pending) {
      try {
        final sessionId = s['id'] as String? ?? 'offline_';
        final docRef = firestore
            .collection('users')
            .doc(user.uid)
            .collection('sessions')
            .doc(sessionId);

        final firestorePayload = Map<String, dynamic>.from(s);
        firestorePayload['startedAt'] = FieldValue.serverTimestamp();
        firestorePayload['endedAt'] = FieldValue.serverTimestamp();
        firestorePayload['syncedFromOffline'] = true;

        await docRef.set(firestorePayload, SetOptions(merge: true));
        syncedCount++;
      } catch (e) {
        debugPrint('Gagal upload sesi offline: ');
        remaining.add(s);
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (remaining.isEmpty) {
        await prefs.remove(_keyPendingSessions);
      } else {
        await prefs.setString(_keyPendingSessions, jsonEncode(remaining));
      }
    } catch (_) {}

    debugPrint('✅ Berhasil menyinkronkan \ sesi offline ke Firestore');
    return syncedCount;
  }

  /// Periksa apakah perangkat sedang memiliki koneksi internet aktif
  static Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ambil titik rute GPS satu sesi (untuk visualisasi rute)
  static Future<List<Map<String, dynamic>>> getGpsTracks(String sessionId) async {
    final user = AuthService.currentUser;
    if (user == null) return [];

    try {
      final querySnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('gps_tracks')
          .orderBy('recordedAt', descending: false)
          .get();

      return querySnapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Firestore getGpsTracks error: $e');
      return [];
    }
  }
  /// Hapus satu sesi riwayat perjalanan
  static Future<bool> deleteSession(String sessionId) async {
    final user = AuthService.currentUser;
    if (user == null) return false;

    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .doc(sessionId)
          .delete();
      return true;
    } catch (e) {
      debugPrint('Error deleteSession: ');
      return false;
    }
  }

  /// Bersihkan semua riwayat perjalanan pengguna
  static Future<bool> clearAllSessions() async {
    final user = AuthService.currentUser;
    if (user == null) return false;

    try {
      final snap = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('sessions')
          .get();

      final batch = firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('Error clearAllSessions: ');
      return false;
    }
  }
}



