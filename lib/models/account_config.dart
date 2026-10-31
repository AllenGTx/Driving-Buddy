import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// ACCOUNT CONFIG — Simpan profil user secara lokal & cache offline
// ============================================================================

import 'package:flutter/foundation.dart';
import '../services/sos_service.dart';

class AccountConfig {
  static final ValueNotifier<String?> photoNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<String> nameNotifier = ValueNotifier<String>('');
  static const _keyName = 'account_name';
  static const _keyEmail = 'account_email';
  static const _keyPhotoUrlPrefix = 'account_photo_url_';

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

  static Future<Map<String, String>> getProfile({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyName) ?? '';
    if (name.isNotEmpty && nameNotifier.value != name) {
      nameNotifier.value = name;
    }
    final email = _resolveEmail(userEmail, prefs);
    final photo = await getPhotoUrl(userEmail: email);
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
    if (photoUrl != null) {
      await setPhotoUrl(photoUrl, userEmail: email);
    }
  }

  static Future<void> setPhotoUrl(String photoUrl, {String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = _resolveEmail(userEmail, prefs);
    await prefs.setString('$_keyPhotoUrlPrefix$email', photoUrl);
    // Simpan juga sebagai fallback global active agar tidak pernah ter-reset
    await prefs.setString('${_keyPhotoUrlPrefix}active', photoUrl);
    photoNotifier.value = photoUrl;
  }

  static Future<String?> getPhotoUrl({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = _resolveEmail(userEmail, prefs);
    var p = prefs.getString('$_keyPhotoUrlPrefix$email');
    if (p == null || p.isEmpty) {
      p = prefs.getString('${_keyPhotoUrlPrefix}active');
    }
    if (p != null && p.isNotEmpty) {
      photoNotifier.value = p;
    }
    return p;
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    await prefs.remove(_keyEmail);
    await prefs.remove('${_keyPhotoUrlPrefix}active');
    photoNotifier.value = null;
    nameNotifier.value = '';
  }
}
