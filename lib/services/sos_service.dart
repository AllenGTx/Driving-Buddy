import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';

class SosService {
  static const _keySosPhone = 'account_sos_phone';
  static const _keySosPhone1 = 'account_sos_phone_1';
  static const _keySosPhone2 = 'account_sos_phone_2';
  static const _keySosPhone3 = 'account_sos_phone_3';

  static const debugEmail = 'buzzerbeater006@gmail.com';
  static const debugPhone = '0895321647135';
  static const String _fonnteToken = 'JZg4cjdMp2x9n5sHNt5M';

  /// Mendapatkan list nomor telepon SOS yang tersimpan (maksimal 3).
  /// Selalu mengembalikan List berukuran 3: [phone1, phone2, phone3].
  static Future<List<String>> getSosPhoneList({String? userEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    String p1 = prefs.getString(_keySosPhone1) ?? prefs.getString(_keySosPhone) ?? '';
    String p2 = prefs.getString(_keySosPhone2) ?? '';
    String p3 = prefs.getString(_keySosPhone3) ?? '';

    final email = userEmail ?? AuthService.currentUser?.email ?? '';
    if (p1.trim().isEmpty && email.toLowerCase().trim() == debugEmail) {
      p1 = debugPhone;
    }

    return [p1.trim(), p2.trim(), p3.trim()];
  }

  /// Backward-compatibility: Mendapatkan nomor telepon SOS pertama
  static Future<String> getSosPhone({String? userEmail}) async {
    final list = await getSosPhoneList(userEmail: userEmail);
    return list.isNotEmpty ? list[0] : '';
  }

  /// Menyimpan hingga 3 nomor kontak SOS ke SharedPreferences lokal dan Firestore.
  static Future<void> saveSosPhoneList(List<String> phones) async {
    final prefs = await SharedPreferences.getInstance();
    final p1 = phones.isNotEmpty ? phones[0].trim() : '';
    final p2 = phones.length > 1 ? phones[1].trim() : '';
    final p3 = phones.length > 2 ? phones[2].trim() : '';

    await prefs.setString(_keySosPhone, p1);
    await prefs.setString(_keySosPhone1, p1);
    await prefs.setString(_keySosPhone2, p2);
    await prefs.setString(_keySosPhone3, p3);

    // Sinkronkan ke Firestore jika user sedang login
    final user = AuthService.currentUser;
    if (user != null) {
      try {
        await firestore.collection('users').doc(user.uid).set({
          'sosPhone': p1,
          'sosPhones': [p1, p2, p3],
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Gagal sinkron SOS phone ke Firestore: $e');
      }
    }
  }

  /// Simpan single phone (Kontak 1)
  static Future<void> saveSosPhone(String phone) async {
    final list = await getSosPhoneList();
    list[0] = phone.trim();
    await saveSosPhoneList(list);
  }

  /// Format nomor HP Indonesia menjadi format internasional WhatsApp (contoh: 0895... -> 62895...).
  static String formatPhoneForWhatsApp(String rawPhone) {
    String cleaned = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '62${cleaned.substring(1)}';
    } else if (cleaned.startsWith('8')) {
      cleaned = '62$cleaned';
    }
    return cleaned;
  }

  /// Membuat teks pesan darurat SOS yang profesional, formal, dan komprehensif.
  static String buildEmergencyMessage({
    required String driverName,
    required String email,
    required double lat,
    required double lng,
    required double speedKmh,
  }) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} - ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
    final mapsUrl = "https://maps.google.com/?q=$lat,$lng";
    final osmUrl = "https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng";

    return "🚨 *PERNYATAAN DARURAT SOS - DRIVING BUDDY* 🚨\n\n"
        "Saya membutuhkan bantuan darurat! Saya memicu Darurat SOS otomatis melalui aplikasi pemantau keselamatan berkendara DrivingBuddy.\n\n"
        "⚠️ *KONDISI DARURAT:* Pengemudi telah dideteksi tertidur lelap / mengalami microsleep. "
        "Alarm peringatan intensitas tinggi telah aktif selama *1 MENIT PENUH* tanpa respons tombol 'Saya Sudah Bangun'. "
        "Kendaraan terindikasi dalam potensi bahaya.\n\n"
        "👤 *Data Pengemudi:*\n"
        "• Nama: $driverName\n"
        "• Akun Terdaftar: $email\n"
        "• Waktu Insiden: $timeStr WIB\n"
        "• Kecepatan Terakhir: ${speedKmh.toStringAsFixed(0)} km/jam\n\n"
        "📍 *Tautan Langsung Peta Lokasi GPS Terkini:*\n"
        "• Google Maps: $mapsUrl\n"
        "• OpenStreetMap: $osmUrl\n"
        "• Titik Koordinat: $lat, $lng\n\n"
        "*(Titik koordinat di atas merupakan posisi GPS tepat pengemudi saat sinyal SOS ini dipicu)*\n\n"
        "Mohon pihak keluarga / kontak darurat segera mencoba menghubungi pengemudi melalui telepon, atau segera koordinasikan bantuan darurat ke koordinat lokasi di atas. Terima kasih.";
  }

  /// Mengirimkan pesan SOS ke satu nomor melalui WhatsApp.
  static Future<bool> sendEmergencySos({
    required String rawPhone,
    required String driverName,
    required String email,
    required double lat,
    required double lng,
    required double speedKmh,
  }) async {
    final phone = formatPhoneForWhatsApp(rawPhone);
    if (phone.isEmpty) return false;

    final message = buildEmergencyMessage(
      driverName: driverName,
      email: email,
      lat: lat,
      lng: lng,
      speedKmh: speedKmh,
    );

    // 1. UTAMA: Kirim otomatis 100% tanpa klik send via API Fonnte Gateway
    try {
      final response = await http.post(
        Uri.parse('https://api.fonnte.com/send'),
        headers: {
          'Authorization': _fonnteToken,
        },
        body: {
          'target': phone,
          'message': message,
          'countryCode': '62',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == true) {
          debugPrint('✅ SOS Terkirim otomatis via Fonnte ke $phone');
          return true;
        }
      }
      debugPrint('⚠️ Fonnte gagal respon status true: ${response.body}');
    } catch (e) {
      debugPrint('⚠️ Error kirim otomatis Fonnte: $e');
    }

    // 2. FALLBACK: Jika offline/kuota Fonnte habis, buka WhatsApp bawaan HP
    final encoded = Uri.encodeComponent(message);
    final directWaUri = Uri.parse("whatsapp://send?phone=$phone&text=$encoded");
    final waMeUri = Uri.parse("https://wa.me/$phone?text=$encoded");

    try {
      if (await canLaunchUrl(directWaUri)) {
        return await launchUrl(directWaUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(waMeUri)) {
        return await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error dispatching fallback SOS WhatsApp: $e');
      try {
        return await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    return false;
  }

  /// Mengirimkan pesan SOS ke SELURUH kontak yang tersimpan (1, 2, atau 3 kontak).
  static Future<int> sendEmergencySosToAll({
    required String driverName,
    required String email,
    required double lat,
    required double lng,
    required double speedKmh,
  }) async {
    final phones = await getSosPhoneList(userEmail: email);
    int sentCount = 0;
    for (final rawPhone in phones) {
      if (rawPhone.trim().isNotEmpty) {
        final ok = await sendEmergencySos(
          rawPhone: rawPhone,
          driverName: driverName,
          email: email,
          lat: lat,
          lng: lng,
          speedKmh: speedKmh,
        );
        if (ok) sentCount++;
      }
    }
    return sentCount;
  }
}
