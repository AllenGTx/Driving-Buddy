import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

enum AlertImageMode {
  none,
  custom,
}

enum AlertAudioType {
  defaultSiren, // sounds/alarm.mp3
  loudBeep,     // sounds/beep.wav
  buzzer,       // sounds/buzzer.wav
  customFile,   // File dari penyimpanan HP
}

class AlertConfig {
  static const _keyImageMode = 'alert_image_mode';
  static const _keyCustomImagePath = 'alert_custom_image_path';
  static const _keyAudioType = 'alert_audio_type';
  static const _keyCustomAudioPath = 'alert_custom_audio_path';
  static const _keyCustomAudioName = 'alert_custom_audio_name';

  // Toggle Head Tilt & Head Bob
  static const _keyEnableHeadTilt = 'enable_head_tilt';
  static const _keyEnableHeadBob = 'enable_head_bob';

  /// Status aktifasi fitur Head Tilt (default: true)
  static Future<bool> isHeadTiltEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableHeadTilt) ?? true;
  }

  static Future<void> setHeadTiltEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableHeadTilt, enabled);
  }

  /// Status aktifasi fitur Head Bobbing (default: true)
  static Future<bool> isHeadBobEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnableHeadBob) ?? true;
  }

  static Future<void> setHeadBobEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableHeadBob, enabled);
  }

  /// Mendapatkan mode gambar alert yang sedang aktif (default: none / tanpa meme)
  static Future<AlertImageMode> getImageMode() async {
    final prefs = await SharedPreferences.getInstance();
    String? mode = prefs.getString(_keyImageMode);

    // Cek Firestore jika di lokal belum pernah disimpan
    if (mode == null && AuthService.currentUser != null) {
      try {
        final doc = await firestore.collection('users').doc(AuthService.currentUser!.uid).get();
        if (doc.exists && doc.data()?.containsKey('alertImageMode') == true) {
          mode = doc.get('alertImageMode') as String?;
          if (mode != null) await prefs.setString(_keyImageMode, mode);
        }
      } catch (_) {}
    }

    mode ??= 'none';

    switch (mode) {
      case 'custom':
        final path = prefs.getString(_keyCustomImagePath) ?? '';
        if (path.isNotEmpty && File(path).existsSync()) {
          return AlertImageMode.custom;
        }
        return AlertImageMode.none;
      case 'none':
      default:
        return AlertImageMode.none;
    }
  }

  /// Mendapatkan path file gambar kustom (jika ada dan valid)
  static Future<String?> getCustomImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyCustomImagePath);
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return null;
  }

  /// Menyimpan mode gambar alert (Persisten di dokumen lokal & Firestore)
  static Future<void> setImageMode(AlertImageMode mode, {String? customPath}) async {
    final prefs = await SharedPreferences.getInstance();
    switch (mode) {
      case AlertImageMode.custom:
        await prefs.setString(_keyImageMode, 'custom');
        if (customPath != null && customPath.isNotEmpty) {
          String finalPath = customPath;
          try {
            final srcFile = File(customPath);
            if (srcFile.existsSync()) {
              final docDir = await getApplicationDocumentsDirectory();
              final ext = customPath.contains('.') ? customPath.split('.').last : 'jpg';
              final persistentFile = File('${docDir.path}/persistent_alert_image.$ext');
              if (srcFile.path != persistentFile.path) {
                await srcFile.copy(persistentFile.path);
              }
              finalPath = persistentFile.path;
            }
          } catch (e) {
            debugPrint('Error copy persistent image: $e');
          }
          await prefs.setString(_keyCustomImagePath, finalPath);
        }
        break;
      case AlertImageMode.none:
        await prefs.setString(_keyImageMode, 'none');
        break;
    }

    // Simpan ke Firestore jika user online
    final user = AuthService.currentUser;
    if (user != null) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'alertImageMode': mode == AlertImageMode.custom ? 'custom' : 'none',
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error syncing alertImageMode to Firestore: $e');
      }
    }
  }

  /// Menghapus gambar alert kustom
  static Future<void> removeCustomImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyImageMode, 'none');
    final oldPath = prefs.getString(_keyCustomImagePath);
    if (oldPath != null) {
      try {
        final f = File(oldPath);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    await prefs.remove(_keyCustomImagePath);

    final user = AuthService.currentUser;
    if (user != null) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'alertImageMode': 'none',
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Mendapatkan tipe audio yang sedang aktif
  static Future<AlertAudioType> getAudioType() async {
    final prefs = await SharedPreferences.getInstance();
    String? type = prefs.getString(_keyAudioType);

    // Cek Firestore jika di lokal belum pernah disimpan
    if (type == null && AuthService.currentUser != null) {
      try {
        final doc = await firestore.collection('users').doc(AuthService.currentUser!.uid).get();
        if (doc.exists && doc.data()?.containsKey('alertAudioType') == true) {
          type = doc.get('alertAudioType') as String?;
          if (type != null) await prefs.setString(_keyAudioType, type);
        }
      } catch (_) {}
    }

    type ??= 'default';

    switch (type) {
      case 'beep':
        return AlertAudioType.loudBeep;
      case 'buzzer':
        return AlertAudioType.buzzer;
      case 'custom':
        final path = prefs.getString(_keyCustomAudioPath) ?? '';
        if (path.isNotEmpty && File(path).existsSync()) {
          return AlertAudioType.customFile;
        }
        return AlertAudioType.defaultSiren;
      case 'default':
      default:
        return AlertAudioType.defaultSiren;
    }
  }

  /// Mendapatkan path file audio kustom
  static Future<String?> getCustomAudioPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyCustomAudioPath);
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return null;
  }

  /// Mendapatkan nama audio yang sedang dipilih untuk tampilan UI
  static Future<String> getAudioDisplayName() async {
    final type = await getAudioType();
    switch (type) {
      case AlertAudioType.defaultSiren:
        return 'Sirene Darurat (Bawaan)';
      case AlertAudioType.loudBeep:
        return 'Beep Alarm Peringatan';
      case AlertAudioType.buzzer:
        return 'Klakson / Buzzer Peringatan';
      case AlertAudioType.customFile:
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_keyCustomAudioName) ?? 'Audio Kustom';
    }
  }

  /// Mendapatkan nama file audio kustom untuk disimpan/ditampilkan
  static Future<String?> getCustomAudioName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomAudioName);
  }

  /// Mengatur audio ke preset bawaan
  static Future<void> setAudioPreset(AlertAudioType type) async {
    final prefs = await SharedPreferences.getInstance();
    String typeStr = 'default';
    if (type == AlertAudioType.defaultSiren) {
      typeStr = 'default';
    } else if (type == AlertAudioType.loudBeep) {
      typeStr = 'beep';
    } else if (type == AlertAudioType.buzzer) {
      typeStr = 'buzzer';
    }
    await prefs.setString(_keyAudioType, typeStr);

    final user = AuthService.currentUser;
    if (user != null) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'alertAudioType': typeStr,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error syncing audio preset to Firestore: $e');
      }
    }
  }

  /// Mengatur audio kustom dari file (Disimpan secara permanen di storage aplikasi & Firestore)
  static Future<void> setCustomAudio(String filePath, String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    String finalPath = filePath;
    try {
      final srcFile = File(filePath);
      if (srcFile.existsSync()) {
        final docDir = await getApplicationDocumentsDirectory();
        final ext = filePath.contains('.') ? filePath.split('.').last : 'mp3';
        final persistentFile = File('${docDir.path}/persistent_alert_audio.$ext');
        if (srcFile.path != persistentFile.path) {
          await srcFile.copy(persistentFile.path);
        }
        finalPath = persistentFile.path;
      }
    } catch (e) {
      debugPrint('Error copy persistent audio: $e');
    }

    await prefs.setString(_keyAudioType, 'custom');
    await prefs.setString(_keyCustomAudioPath, finalPath);
    await prefs.setString(_keyCustomAudioName, fileName);

    final user = AuthService.currentUser;
    if (user != null) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'alertAudioType': 'custom',
          'alertAudioName': fileName,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error syncing custom audio to Firestore: $e');
      }
    }
  }

  /// Reset audio ke default
  static Future<void> resetAudio() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioType, 'default');
    final oldPath = prefs.getString(_keyCustomAudioPath);
    if (oldPath != null) {
      try {
        final f = File(oldPath);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    await prefs.remove(_keyCustomAudioPath);
    await prefs.remove(_keyCustomAudioName);

    final user = AuthService.currentUser;
    if (user != null) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'alertAudioType': 'default',
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }
}
