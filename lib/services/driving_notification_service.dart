import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================================
// SERVICE NOTIFIKASI BERKENDARA (ONGOING NOTIFICATION)
// Menampilkan notifikasi berjalan saat pengguna keluar dari aplikasi (ke Home
// atau membuka Google Maps) saat sesi monitoring sedang aktif.
// Saat diklik, notifikasi akan langsung mengembalikan pengguna ke Driving Buddy.
// ============================================================================

class DrivingNotificationService {
  DrivingNotificationService._();
  static final DrivingNotificationService instance =
      DrivingNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  static const int monitoringNotificationId = 8881;
  static const String channelId = 'driving_buddy_monitoring_channel';
  static const String channelName = 'Sesi Berkendara Aktif';
  static const String channelDesc =
      'Menampilkan status pemantauan berkendara Driving Buddy saat di latar belakang';

  /// Inisialisasi awal notifikasi & pembuatan channel Android
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('🔔 Pengguna mengetuk notifikasi Driving Buddy');
        },
      );

      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();

        const androidChannel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDesc,
          importance: Importance.high,
          enableVibration: false,
          playSound: false,
        );
        await androidImpl.createNotificationChannel(androidChannel);
      }

      _isInitialized = true;
      debugPrint('✅ DrivingNotificationService berhasil diinisialisasi');
    } catch (e) {
      debugPrint('⚠️ DrivingNotificationService init warning: $e');
    }
  }

  /// Tampilkan notifikasi persisten (ongoing) saat monitoring aktif
  Future<void> showMonitoringNotification({int? durationSeconds}) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      String body =
          'Driving Buddy aktif memantau kewaspadaan. Ketuk untuk kembali ke aplikasi.';
      if (durationSeconds != null && durationSeconds > 0) {
        final m = durationSeconds ~/ 60;
        final s = durationSeconds % 60;
        final durStr = m > 0 ? '$m menit $s detik' : '$s detik';
        body =
            'Sesi aktif ($durStr). AI memantau kantuk. Ketuk untuk kembali.';
      }

      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.public,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        id: monitoringNotificationId,
        title: '🚗 Sesi Berkendara Sedang Berlangsung',
        body: body,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('⚠️ Gagal memunculkan notifikasi ongoing: $e');
    }
  }

  /// Hapus notifikasi ongoing saat sesi selesai
  Future<void> cancelMonitoringNotification() async {
    try {
      await _notificationsPlugin.cancel(id: monitoringNotificationId);
    } catch (_) {}
  }
}
