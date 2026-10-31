import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sos_service.dart';

// ============================================================================
// ACCOUNT CONFIG — Simpan profil user secara lokal & cache offline
// ============================================================================

class AccountConfig {
  /// Notifier untuk foto profil kustom Driving Buddy (ditampilkan di App Bar kanan atas)
  static final ValueNotifier<String?> photoNotifier = ValueNotifier<String?>(null);

  /// Notifier untuk foto akun Google (ditampilkan di samping "Selamat Malam, [Nama]")
  static final ValueNotifier<String?> googlePhotoNotifier = ValueNotifier<String?>(null);

  /// Notifier untuk nama pengemudi
  static final ValueNotifier<String> nameNotifier = ValueNotifier<String>('');

  static const _keyName = 'account_name';
  static const _keyEmail = 'account_email';
  static const _keyCustomPhotoPrefix = 'account_custom_photo_';
  static const _keyGooglePhotoPrefix = 'account_google_photo_';

  static Future<String> getSosPhone({String? userEmail}) => SosService.getSosPhone(userEmail: userEmail);
  static Future<void> setSosPhone(String phone) => SosService.saveSosPhone(phone);

  static String _resolveEmail(String? userEmail, SharedPreferences prefs) {
    if (userEmail != null && userEmail.trim().isNotEmpty) {
      return userEmail.trim().toLowerCase();
    }
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    if (authEmail != null && authEmail.trim().isNotEmpty) {
      return authEmail.trim().toLowerCase();
    }
    final savedEmail = prefs.getString(_keyEmail);
    if (savedEmail != null && savedEmail.trim().isNotEmpty) {
      return savedEmail.trim().toLowerCase();
    }
    return 'guest';
  }

  static String _resolveUid(String? uid) {
    if (uid != null && uid.trim().isNotEmpty) {
      return uid.trim();
    }
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.trim().isNotEmpty) {
      return authUid.trim();
    }
    return 'guest';
  }

  static Future<Map<String, String>> getProfile({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyName) ?? '';
    if (name.isNotEmpty && nameNotifier.value != name) {
      nameNotifier.value = name;
    }
    final email = _resolveEmail(userEmail, prefs);
    final photo = await getCustomPhoto(userEmail: email);
    return {
      'name': name,
      'email': email,
      'photoUrl': photo ?? '',
    };
  }

  static Future<void> saveProfile(String name, String email, {String? photoUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyEmail, email);
    nameNotifier.value = name;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      await setCustomPhoto(photoUrl, userEmail: email);
    }
  }

  /// Simpan Foto Profil Kustom Driving Buddy (HANYA untuk App Bar kanan atas)
  /// Disimpan per email dan per UID agar 1 akun 1 foto dan tidak hilang saat logout
  static Future<void> setCustomPhoto(String photoUrl, {String? userEmail, String? uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = _resolveEmail(userEmail, prefs);
    final userUid = _resolveUid(uid);

    await prefs.setString('$_keyCustomPhotoPrefix$email', photoUrl);
    await prefs.setString('$_keyCustomPhotoPrefix$userUid', photoUrl);
    await prefs.setString('${_keyCustomPhotoPrefix}active', photoUrl);
    photoNotifier.value = photoUrl;
  }

  /// Ambil Foto Profil Kustom Driving Buddy
  static Future<String?> getCustomPhoto({String? userEmail, String? uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = _resolveEmail(userEmail, prefs);
    final userUid = _resolveUid(uid);

    var p = prefs.getString('$_keyCustomPhotoPrefix$email');
    if (p == null || p.isEmpty) {
      p = prefs.getString('$_keyCustomPhotoPrefix$userUid');
    }
    if (p == null || p.isEmpty) {
      p = prefs.getString('${_keyCustomPhotoPrefix}active');
    }
    if (p != null && p.isNotEmpty) {
      photoNotifier.value = p;
    }
    return p;
  }

  /// Backward compatibility
  static Future<void> setPhotoUrl(String photoUrl, {String? userEmail}) async {
    await setCustomPhoto(photoUrl, userEmail: userEmail);
  }

  /// Backward compatibility
  static Future<String?> getPhotoUrl({String? userEmail}) async {
    return getCustomPhoto(userEmail: userEmail);
  }

  /// Simpan Foto Akun Google (HANYA untuk samping "Selamat Malam, [Nama]")
  static Future<void> setGooglePhoto(String? photoUrl, {String? userEmail}) async {
    if (photoUrl == null || photoUrl.isEmpty) {
      googlePhotoNotifier.value = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final email = _resolveEmail(userEmail, prefs);
    await prefs.setString('$_keyGooglePhotoPrefix$email', photoUrl);
    await prefs.setString('${_keyGooglePhotoPrefix}active', photoUrl);
    googlePhotoNotifier.value = photoUrl;
  }

  /// Ambil Foto Akun Google
  static Future<String?> getGooglePhoto({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = _resolveEmail(userEmail, prefs);
    var p = prefs.getString('$_keyGooglePhotoPrefix$email');
    if (p == null || p.isEmpty) {
      p = prefs.getString('${_keyGooglePhotoPrefix}active');
    }
    if (p != null && p.isNotEmpty) {
      googlePhotoNotifier.value = p;
    }
    return p;
  }

  /// Saat logout: bersihkan state sesi aktif, tapi JANGAN hapus cache per-akun
  /// agar ketika user login kembali, foto kustom akun tersebut tetap ada!
  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    await prefs.remove(_keyEmail);
    await prefs.remove('${_keyCustomPhotoPrefix}active');
    await prefs.remove('${_keyGooglePhotoPrefix}active');
    photoNotifier.value = null;
    googlePhotoNotifier.value = null;
    nameNotifier.value = '';
  }
}
