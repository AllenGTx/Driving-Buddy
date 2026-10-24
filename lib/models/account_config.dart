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
  static const _keyLegacyPhotoUrl = 'account_photo_url';

  static Future<String> getSosPhone({String? userEmail}) => SosService.getSosPhone(userEmail: userEmail);
  static Future<void> setSosPhone(String phone) => SosService.saveSosPhone(phone);

  static Future<Map<String, String>> getProfile({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyName) ?? '';
    if (name.isNotEmpty && nameNotifier.value != name) {
      nameNotifier.value = name;
    }
    final email = userEmail ?? prefs.getString(_keyEmail) ?? '';
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
    final email = (userEmail != null && userEmail.trim().isNotEmpty)
        ? userEmail.trim().toLowerCase()
        : (prefs.getString(_keyEmail)?.trim().toLowerCase() ?? 'guest');
    await prefs.setString('$_keyPhotoUrlPrefix$email', photoUrl);
    photoNotifier.value = photoUrl;
  }

  static Future<String?> getPhotoUrl({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = (userEmail != null && userEmail.trim().isNotEmpty)
        ? userEmail.trim().toLowerCase()
        : (prefs.getString(_keyEmail)?.trim().toLowerCase() ?? 'guest');
    final p = prefs.getString('$_keyPhotoUrlPrefix$email');
    photoNotifier.value = p;
    return p;
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    await prefs.remove(_keyEmail);
    photoNotifier.value = null;
    nameNotifier.value = '';
  }
}
